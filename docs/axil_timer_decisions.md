# axil_timer decisions log

every question I found while reading `axil_timer_spec.md` and ARM IHI 0022E. where
it came from, what I decided, and why. the rtl and the benches both do exactly
what is in these tables.

the point of writing it down first is that none of it is left for the rtl to
decide by accident. if a row here is wrong, the design is wrong in a way I can
argue about. if a row is missing, that is the bug.

## principles for same cycle collisions

most of the hard questions are the same question. hardware and software both want
to change one thing in one cycle. who wins?

**events are never lost.** hardware reports something happened, an expiry, in the
same cycle software clears the report. the report survives. losing it means
software waits forever for a thing that already happened.

**software's newest intent wins for configuration and state.** software writes a
value in the same cycle hardware would change it. the written value is what stays.

**a cycle's event is a fact about that cycle.** whether an expiry happened is
computed from the values that were there during the cycle. a write in that same
cycle cannot un-happen it.

## bus questions

| question | where it came from | decision | reason |
|---|---|---|---|
| use WSTRB or ignore it? | IHI 0022E B1.1.3 allows use, ignore, or error | use fully, byte by byte | lets software change one byte without disturbing others |
| what does a write with WSTRB all zero do? | B1.3.1 says such writes can reach a slave | changes nothing, no side effects, OKAY if the address is valid | a write that selects no bytes writes nothing |
| write to COUNT (read-only)? | spec says RO only | SLVERR, no change | A3.4.4 lists a write to a read-only location as a slave error condition |
| offsets that are not multiples of 4? | spec lists offsets only | SLVERR | section 6 says unlisted offsets get SLVERR, and 0x01 is unlisted |
| read of reserved bits? | spec marks them reserved | read as zero | standard RAZ convention |
| write of reserved bits? | spec marks them reserved | ignored | standard WI convention |
| read data for a SLVERR read? | not stated | zero | never leak stale data on an error |
| which COUNT value does a read return? | not stated | the value during the cycle of the AR handshake | the read is sampled when the address is accepted |
| read and write of the same register in one cycle? | not stated | the read returns the value before the write | a write takes effect at the end of its cycle |
| AWPROT, ARPROT? | section 6 | accepted and ignored | block has no security partitioning |
