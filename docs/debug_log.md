# Debug log

What broke while building this and while moving it to systemverilog. Numbers are
from real runs.

The design was not the problem in any of these. They are the testbench or the
tool, and one of them had been wrong from the first day and nothing ever told me.

---

## 1. sixteen continuous assignments turned into one time initialisers

**Symptom.** Converted the rtl from verilog to systemverilog. Lint clean. Then the
bench:

```
RESULT: FAIL (timeout)
```

Not a mismatch. A timeout. Nothing moved at all.

**The cause.** The conversion was scripted and one of the rules was `wire` becomes
`logic`. That rule is wrong.

```verilog
wire  tick = en & (pre_q >= prescale);    // continuous assignment, re-evaluates
logic tick = en & (pre_q >= prescale);    // a variable with an initial value
```

Same shape, completely different meaning. The first is a gate. The second is
evaluated once before time zero and never again. So `tick` was stuck at whatever
it started as and the counter never counted.

**How I found it.** Grepped for the shape.

```
grep -rn '^\s*logic\s.*=' rtl/ | grep -v '=='
```

**The fix.** Declaration and assignment split.

```systemverilog
logic tick;
assign tick = en & (pre_q >= prescale);
```

**What I take from it.** Lint passing meant nothing here. The design linted clean
while it could not count. A conversion is only done when the numbers say it is:
1891 AW handshakes, 1831 writes, 21706 cycles compared, same before and after.

---

## 2. the script that fixed it also had a bug

The fixer gathered a statement by reading lines until one ended in a semicolon.
That is wrong when a comment sits after the semicolon.

```systemverilog
logic aw_hs = s_axil_awvalid & s_axil_awready;   // AW handshake this cycle
```

The line does not end in `;`, it ends in a comment. So the gatherer kept eating
the next lines, and those were five more declarations with the same problem.
First pass reported "1 restored" for a file that had six.

**The fix.** Strip the comment before testing for the semicolon. Second pass found
seven more, so seventy seven in total.

**What I take from it.** After a scripted edit, grep again for the pattern you
were fixing. The count is the check. "It said it fixed one" is not a check.

---

## 3. reset was never actually asserted, in any run, ever

This is the one that had been wrong from the beginning.

**Symptom.** Two protocol violations on the very first clock edge:

```
[5000] timer CHECK FAIL: BVALID not low during reset
[5000] timer CHECK FAIL: RVALID not low during reset
```

**First thought.** My conversion broke something. Reasonable, and wrong.

**How I checked.** Took the original verilog, unconverted, and compiled it with
the newer language flag. Same two failures. So it was not the conversion. It was
`-g2005` against `-g2012`.

**The cause.** The bench declared reset like this:

```verilog
reg aresetn = 1'b0;
```

Reset is low at time zero. The design resets asynchronously:

```systemverilog
always_ff @(posedge aclk or negedge aresetn)
```

There is no falling edge, because it was never high. So the reset branch never
runs and every flip flop in the bus front end holds X until the first clock edge.
The checker was right. BVALID really was not low during reset. It was X.

**The fix.** Two lines.

```systemverilog
reg aresetn = 1'b1;
initial begin
    #1 aresetn = 1'b0;
end
```

**What I take from it.** The stricter language mode paid for itself here. Nothing
had ever failed because of this. The X cleared after one edge and every test
passed for weeks. It was still wrong, and an asynchronous reset that never fires
is exactly the sort of thing that behaves differently in silicon.

---

## 4. my own assertion was wrong about the protocol

**Symptom.** Wrote the AXI4-Lite assertions, bound them, ran the bench.

```
[9525000] %Error: Assertion failed in ...u_sva.a_aw_independent:
          axil: AWREADY appears to be waiting for WVALID
```

**First thought.** Found a real bug in the bus front end. It was not one.

**The cause.** I had written the rule like this:

```systemverilog
(awvalid && !wvalid) |-> ##[0:3] awready
```

Meaning: offer an address with no data and the slave must take it within three
cycles. That is not the rule. The real rule is the slave must not *wait for the
other channel*. A slave that is simply full is allowed to hold AWREADY low as long
as it likes, and this one was full, from an earlier write whose response had not
been collected.

**The fix.** Give the checker the slave's own occupancy, which it can see because
it is bound inside the module.

```systemverilog
(awvalid && !wvalid && !aw_full) |-> awready
```

Refusing because you are full is legal. Refusing because the other half has not
arrived is not. From the pins alone you cannot tell them apart.

**What I take from it.** A failing assertion is a claim about the spec, and the
claim can be mine rather than the design's. First question is which one.

---

## 5. always_comb that never ran, in one simulator only

**Symptom.** Brought the uvm bench up under xsim. It hung. So did the directed
bench, which had been passing under icarus and verilator for weeks.

```
[5000]  rstn=0 bvq=0 bvd=x
[45000] rstn=1 bvq=0 bvd=x
[55000] rstn=1 bvq=x rvd=x
```

`bvalid_q` resets to 0 like it should. `bvalid_d` is X and stays X, and one edge
after reset lifts the X back into the register.

**Narrowing it.** First job was to get the uvm out of the way. Forty lines, the
bus front end on its own, no classes:

```
[25000] rstn=1 bvq=0 bvd=x rvq=0 rvd=x awrdy=1
[35000] rstn=1 bvq=x bvd=x rvq=x rvd=x awrdy=1
```

Same thing. Not the bench then.

The `always_comb` that computes `bvalid_d` starts by assigning every stored value
to itself, so `bvalid_d` cannot be X unless the block never runs. It has one
driver and there is no loop. Then I put a `$display` at the top of it to prove it
never ran, and the design started working.

A probe that fixes the thing it is measuring means the probe is not the subject
any more, the tool is. `-O0` did not change it, neither did `--debug typical`,
neither did writing `always @(*)` instead.

**The cause.** Bisecting the block, one statement at a time, landed on this:

```systemverilog
if (b_hs)
    bvalid_d = 1'b0;
```

With `begin` and `end` around that one statement, everything comes right. Without
them xsim loses the variable. `if (r_hs) rvalid_d = 1'b0;` broke the read side the
same way and was fixed by the same thing.

**The fix.** `begin` / `end` on both. No logic changed.

**What I take from it.** The rtl was correct and two simulators agreed with it.
That is not proof. The minimal reproducer is what turns "xsim is being strange"
into something I can point at, and the forty line version took less time than the
half hour I spent staring at the real one.

---

## 6. a clocking block input that sampled X forever

**Symptom.** With the hang fixed the bench ran, 2000 accesses, and there was one
error, in the first read:

```
ACC_READ addr 0xxxx answered 00, expected 10
```

The monitor recorded an X address. The scoreboard looked X up in the register map,
did not find it, expected SLVERR, and the design had answered OKAY. The design was
right. The address really was 0x000.

**How I found it.** Printed both the sampled value and the raw pin every cycle:

```
DBG[105000] cb.araddr=xxxxxxxxxxxx cb.awaddr=xxxxxxxxxxxx cb.wdata=xxxxxxxx cb.rdata=00000000
```

`rdata` samples fine. `araddr`, `awaddr` and `wdata` are X for the whole run. The
three that break are the ones the driver drives; `rdata` comes from the design.

**The cause.** The interface declared them with an initialiser:

```systemverilog
logic [ADDR_W-1:0] araddr  = '0;
```

and the driver's idle task drives `'0` into the same signal. Two zeros, so the
value never changes, so no event. xsim's clocking block input starts at X and only
updates when the signal changes, and this one never did. The first read went to
`CTRL` at offset 0, which is also zero, so still nothing moved. Every later read
went somewhere non zero, the sample woke up, and the remaining 903 passed. One
error out of 2000 because exactly one access sat in the hole.

**The fix.** Dropped the initialisers on the payload signals. The idle task's
write is now a real X to 0 transition. Addresses and data being X before the
driver starts is legal on this bus anyway, and the valid signals keep theirs so
the protocol checker still has something true to check during reset.

**What I take from it.** One failure out of two thousand reads like noise and it
was not, and the thing that made it findable was that the scoreboard prints the
address it judged rather than just saying mismatch.

---

## Where it stands

```
CHECKER timer: AW 1891, W 1891, B 1891, AR 1443, R 1443 handshakes, 0 rule violations
SCOREBOARD: 1831 writes, 1383 reads, 0 errors, 0 model mismatches over 21706 cycles
RESULT: PASS

SCOREBOARD: 2000 accesses checked, 0 errors
COVERAGE:   cg_acc 100.00% over 2000 samples
COVER responses okay / slverr   : 1541 / 459
COVER writes partial / nostrobe : 359 / 111
```
