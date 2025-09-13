# axil_timer spec

What the block does, written before any rtl. Rev 0.3.

Down counting timer on an axi4-lite slave port with a level interrupt. Software
puts a start value in, picks one shot or periodic, enables it. It counts down at
whatever rate the prescaler says and raises irq when it gets to the end.

Anything this file does not answer is a row in axil_timer_decisions.md.

## Interfaces

| Signal group      | Description                                                   |
|-------------------|---------------------------------------------------------------|
| `aclk`, `aresetn` | Single clock, active-low reset, shared with the AXI4-Lite bus |
| AXI4-Lite slave   | 32-bit data. Address width set by parameter `ADDR_W`, default 12 |
| `irq`             | Active-high level interrupt                                   |

Axi4-lite the way ARM IHI 0022E part B defines it.

## Register map

All 32 bits wide. Offsets are from the base of the block.

| Offset | Name     | Access | Reset      | Description                   |
|--------|----------|--------|------------|-------------------------------|
| 0x00   | CTRL     | RW     | 0x00000000 | Control                       |
| 0x04   | LOAD     | RW     | 0x00000000 | Reload value                  |
| 0x08   | COUNT    | RO     | 0x00000000 | Current counter value         |
| 0x0C   | STATUS   | W1C    | 0x00000000 | Status flags                  |
| 0x10   | PRESCALE | RW     | 0x00000000 | Prescaler divide value        |

### CTRL

| Bits  | Field    | Description                                                 |
|-------|----------|-------------------------------------------------------------|
| 0     | EN       | 1 enables counting                                          |
| 1     | PERIODIC | 0 one-shot, 1 periodic                                      |
| 2     | IRQ_EN   | 1 enables the interrupt output                              |
| 31:3  | Reserved |                                                             |

### LOAD

| Bits  | Field | Description                                                    |
|-------|-------|----------------------------------------------------------------|
| 31:0  | LOAD  | Value loaded into COUNT                                        |

Writing LOAD also drops the value into COUNT and restarts the prescaler.

### COUNT

| Bits  | Field | Description                                                    |
|-------|-------|----------------------------------------------------------------|
| 31:0  | COUNT | Current value of the down counter                              |

### STATUS

| Bits  | Field    | Description                                                 |
|-------|----------|-------------------------------------------------------------|
| 0     | EXPIRED  | Set when the timer expires. Write 1 to clear                |
| 31:1  | Reserved |                                                             |

### PRESCALE

| Bits  | Field    | Description                                                 |
|-------|----------|-------------------------------------------------------------|
| 15:0  | PRESCALE | The counter is decremented once every PRESCALE+1 clock cycles |
| 31:16 | Reserved |                                                             |

## How it runs

EN is 1, so the prescaler makes a tick once every PRESCALE+1 clocks.

On a tick:

- COUNT not zero, take one off it
- COUNT zero, it expired. Set EXPIRED. Periodic reloads COUNT from LOAD, one shot
  Clears EN and leaves COUNT at zero

EN is 0, COUNT just holds.

So periodic works out at (PRESCALE+1) x (LOAD+1) clocks.

## Irq

`irq` is high while EXPIRED and IRQ_EN are both 1. A level, not a pulse.

## The bus

Anything at an offset not in the map above gets SLVERR.

AWPROT and ARPROT are taken and ignored, there is nothing to protect here.
