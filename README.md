# axil-timer

AXI4-Lite timer. Down counter with a prescaler, one shot or periodic, and a level
interrupt.

`docs/axil_timer_spec.md` is the spec. `docs/axil_timer_decisions.md` is every
question the spec did not answer and what I decided.

The bench has a reference model beside the design and compares every register
every cycle.

Needs icarus verilog and verilator.

```
make lint
make run
make regress
make waves
```
