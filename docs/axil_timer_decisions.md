# axil_timer decisions log

Every question I found while reading `axil_timer_spec.md` and ARM IHI 0022E. Where
it came from, what I decided, and why. The rtl and the benches both do exactly
what is in these tables.

The point of writing it down first is that none of it is left for the rtl to
decide by accident. If a row here is wrong, the design is wrong in a way I can
argue about. If a row is missing, that is the bug.

## Principles for same cycle collisions

Most of the hard questions are the same question. Hardware and software both want
to change one thing in one cycle. Who wins?

**Events are never lost.** Hardware reports something happened, an expiry, in the
same cycle software clears the report. The report survives. Losing it means
software waits forever for a thing that already happened.

**Software's newest intent wins for configuration and state.** Software writes a
value in the same cycle hardware would change it. The written value is what stays.

**A cycle's event is a fact about that cycle.** Whether an expiry happened is
computed from the values that were there during the cycle. A write in that same
cycle cannot un-happen it.

## Bus questions

| Question | Where it came from | Decision | Reason |
|---|---|---|---|
| Use WSTRB or ignore it? | IHI 0022E B1.1.3 allows use, ignore, or error | Use fully, byte by byte | Lets software change one byte without disturbing others |
| What does a write with WSTRB all zero do? | B1.3.1 says such writes can reach a slave | Changes nothing, no side effects, OKAY if the address is valid | A write that selects no bytes writes nothing |
| Write to COUNT (read-only)? | Spec says RO only | SLVERR, no change | A3.4.4 lists a write to a read-only location as a slave error condition |
| Offsets that are not multiples of 4? | Spec lists offsets only | SLVERR | Section 6 says unlisted offsets get SLVERR, and 0x01 is unlisted |
| Read of reserved bits? | Spec marks them reserved | Read as zero | Standard RAZ convention |
| Write of reserved bits? | Spec marks them reserved | Ignored | Standard WI convention |
| Read data for a SLVERR read? | Not stated | Zero | Never leak stale data on an error |
| Which COUNT value does a read return? | Not stated | The value during the cycle of the AR handshake | The read is sampled when the address is accepted |
| Read and write of the same register in one cycle? | Not stated | The read returns the value before the write | A write takes effect at the end of its cycle |
| AWPROT, ARPROT? | Section 6 | Accepted and ignored | Block has no security partitioning |

## Timer questions

| Question | Where it came from | Decision | Reason |
|---|---|---|---|
| When is the first tick after enabling? | Section 4 gives a rate, not a phase | Prescaler held at 0 while EN is 0. First tick in the (PRESCALE+1)th cycle with EN high | Makes the first period equal to every later period |
| PRESCALE made smaller than the prescaler's current value? | Section 3.5 gives no timing for changes | Tick at once (compare uses greater-or-equal) | An equality compare would wrap round for up to 65536 cycles |
| Does a LOAD write with no strobes restart COUNT? | Section 3.2 | No | No byte of LOAD was written |
| LOAD write in the same cycle as an expiry? | Not stated | COUNT takes the written value, the prescaler restarts, EXPIRED is still set, one-shot mode still clears EN | Events never lost, software intent wins for COUNT |
| CTRL write in the same cycle as a one-shot expiry? | Not stated | The written EN value wins | Software intent wins for configuration |
| Write-1-to-clear in the same cycle as an expiry? | Not stated | EXPIRED stays 1 | Events never lost |
| PERIODIC changed in the same cycle as an expiry? | Not stated | The expiry uses the old mode | The event is a fact about the values present during that cycle |
| EN set when COUNT is already 0? | Not stated | Expires on the first tick | Follows directly from section 4 |
| Irq when IRQ_EN is set while EXPIRED is already 1? | Section 5 | Irq rises at once | Irq is a level, the AND of two register bits |
