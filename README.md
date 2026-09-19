# axil-timer

A programmable down counting timer with an AXI4-Lite slave port, in SystemVerilog.

Written spec first. The specification, then every question the specification does
not answer written down and decided with a reason, then the rtl. Both files are in
`docs/` and they are the ones worth reading.

The bus front end, the protocol checker and the assertions in here are meant to be
reused. [axil-uart16550](https://github.com/mij001/axil-uart16550) takes this repo
as a submodule and uses all three unchanged.

Every number below is from a run on this machine.

## The register map

| Offset | Name | Access | What |
|---|---|---|---|
| 0x00 | CTRL | RW | EN, PERIODIC, IRQ_EN |
| 0x04 | LOAD | RW | Reload value, writing it also reloads COUNT and restarts the prescaler |
| 0x08 | COUNT | RO | The down counter |
| 0x0C | STATUS | W1C | EXPIRED |
| 0x10 | PRESCALE | RW | Decrement once every PRESCALE+1 cycles |

Three modules behind a shared bus front end. `axil_reg_bus` turns the five
AXI4-Lite channels into a small register bus, `axil_timer_regs` is the map and the
collision rules, `axil_timer_core` is the prescaler and the counter.

There is no clock divider anywhere. The prescaler makes a one cycle enable and
everything runs on `aclk`. Dividing a clock with flip flops makes a second clock
domain, which is the mistake this design is avoiding.

`make waves` dumps the short scenarios to `sim/timer_*.vcd` if you want to watch a
one-shot run in gtkwave.

## The decisions log

`docs/axil_timer_decisions.md` is the interesting file. Every row is a question
the spec raised, where it came from, what I decided and why. Three principles
settle most of it:

- **Events are never lost.** Hardware sets a flag in the same cycle software
  clears it, the flag stays set.
- **Software's newest intent wins** for configuration and stored data.
- **A cycle's event is a fact about that cycle.** A write in that cycle cannot
  un-happen it.

Some rows:

| Question | Decision | Why |
|---|---|---|
| PRESCALE shrunk below the prescaler's current value | Tick at once, compare is `>=` | An equality compare would wrap round for up to 65536 cycles |
| Write-1-to-clear in the same cycle as an expiry | EXPIRED stays 1 | Events are never lost |
| Write with WSTRB all zero | Nothing changes, OKAY if the address is valid | A write that selects no bytes writes nothing |

Every one of those is a row the bench has to prove it notices.

## How it is checked

Three things, and they overlap on purpose.

**A directed bench** with a Verilog reference model beside the design, every
register compared every cycle. 23 coverage counters, and the ones that matter are
the same cycle collisions.

```
CHECKER timer: AW 1891, W 1891, B 1891, AR 1443, R 1443 handshakes, 0 rule violations
SCOREBOARD: 1831 writes, 1383 reads, 0 errors, 0 model mismatches over 21706 cycles
RESULT: PASS
```

**Assertions.** `sva/axil_sva.sv` states the AXI4-Lite rules as SVA and binds them
onto `axil_reg_bus`, so no design file mentions them.

```systemverilog
a_w_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (wvalid && !wready) |=> ($stable(wdata) && $stable(wstrb)))
```

`tb/common/axil_checker.sv` says the same things by hand and runs under icarus
too. Both are kept.

**A uvm bench.** Item, sequence, sequencer, driver, monitor, scoreboard,
coverage, agent, env and test, in one package, built and connected in
`build_phase` / `connect_phase` / `run_phase` / `report_phase`.

This is the uvm 1.2 library, the copy that ships inside vivado, run under xsim.
`make uvm` needs vivado for that reason and nothing else does.

The scoreboard is a shadow of the register map and never looks at a pin.

```
SCOREBOARD: 2000 accesses checked, 0 errors
COVERAGE:   cg_acc 100.00% over 2000 samples
COVER responses okay / slverr   : 1541 / 459
```

The stimulus is `rand` fields with `dist` weights on the sequence item and xsim
solves them, so the weights above are the solver's, not mine.

## Running it

Needs icarus verilog and verilator. `make uvm` also needs vivado.

```
make lint       verilator -Wall on the rtl
make run        directed bench with the reference model
make regress    ten seeds
make sva        the same bench with the assertions bound
make uvm        uvm bench under xsim, constrained random
make waves      scenarios to sim/timer_*.vcd, for gtkwave
```

Verilator `-Wall` is clean. Icarus prints
`sorry: Case unique/unique0 qualities are ignored` on every `unique case`, so that
check only really runs under verilator.

## Not there yet

Simulation only. Not synthesised, so no area figure, no timing closure and no
fpga.

One agent and one interface in the uvm bench. No virtual sequencer and no
layering across two interfaces, which is where a uvm environment starts to earn
its shape.

Functional coverage is on the bus accesses. No toggle coverage and no fsm arc
coverage. The interrupt is only checked against the reference model.

What broke while building it, and how I found each one, is in
[docs/debug_log.md](docs/debug_log.md).
