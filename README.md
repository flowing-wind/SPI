# SPI

A synthesizable SPI (Serial Peripheral Interface) IP core with a 32-bit **APB**
slave interface. The programming model follows the Motorola/Freescale **S12 SPI
(S12SPIV4)** block guide, extended with a selectable **8 / 16 / 32-bit frame
width**.

## Features

- APB3 slave interface, 32-bit data bus, zero wait states
- Master and slave modes
- All four SPI modes (CPOL / CPHA), MSB- or LSB-first
- Programmable frame width: 8, 16 or 32 bits (SPIFW register, placed at the
  offset that is reserved in the original S12 register map)
- Baud-rate generator, divisor 2…2048: `(SPPR+1) × 2^(SPR+1)`
- Double-buffered TX and RX; back-to-back transfers in master mode (CPHA = 1)
- Automatic slave-select output (SSOE) with guaranteed leading/trailing/idle times
- Bidirectional single-wire mode (MOMI / SISO)
- Mode-fault detection with automatic master-to-slave demotion
- S12-style status flags (SPIF / SPTEF / MODF) and a single maskable interrupt
- Single PCLK clock domain; all pad inputs synchronized (no ext-clocked logic)

## Directory Structure

```
SPI/
├── rtl/                  Synthesizable Verilog-2001 RTL
│   ├── spi_top.v         Top level (APB + pad interface)
│   ├── spi_regs.v        Register file / flag protocol / IRQ
│   ├── spi_fsm_top.v     Mode control, config-change abort
│   ├── spi_master.v      Master transfer engine
│   ├── spi_slave.v       Slave transfer engine
│   ├── spi_baud_gen.v    Baud-rate / SCK generator
│   └── spi_cdc_sync.v    Pad input synchronizers / edge detect
├── tb/
│   └── tb_spi.sv         Self-checking functional testbench
└── Doc/
    ├── SPI_Datasheet.md  Full datasheet (registers, protocol, examples)
    └── motorola_freescale_nxp_spi_manual_2000.pdf   Reference manual
```

## Register Map (word offsets)

| Offset | Register | Access | Description |
|--------|----------|--------|-------------|
| 0x00 | SPICR1 | R/W | Control 1: SPIE, SPE, SPTIE, MSTR, CPOL, CPHA, SSOE, LSBFE |
| 0x04 | SPICR2 | R/W | Control 2: MODFEN, BIDIROE, SPISWAI, SPC0 |
| 0x08 | SPIBR | R/W | Baud rate: SPPR, SPR |
| 0x0C | SPISR | R | Status: SPIF, SPTEF, MODF |
| 0x10 | SPIFW | R/W | Frame width: 8 / 16 / 32-bit |
| 0x14 | SPIDR | R/W | Data (TX on write, RX on read) |

See [Doc/SPI_Datasheet.md](Doc/SPI_Datasheet.md) for bit-level detail,
functional description and APB programming examples.

## Quick Start (simulation)

Requires [Icarus Verilog](http://iverilog.icarus.com/):

```sh
cd tb
iverilog -g2012 -o spi_tb.vvp ../rtl/*.v tb_spi.sv
vvp spi_tb.vvp
```

All simulation outputs (`spi_tb.vvp`, `tb_spi.vcd`) are produced inside `tb/`.

Expected output: `TEST PASSED : 80 checks, 0 errors`. The bench connects two
`spi_top` instances (master ↔ slave) pad-to-pad and exercises registers, all
SPI modes and frame widths, flag protocols, back-to-back transfers,
bidirectional mode and mode fault.

## Integration Notes

- Connect each `*_pad_i/o/oe` triple to a tri-state pad:
  `pad = oe ? o : Hi-Z`, `i = pad`.
- The core runs entirely on `PCLK`; in slave mode keep the external
  SCK ≤ `f_PCLK / 6` (edges are detected through synchronizers).
- `PREADY` is tied high; `PADDR[1:0]` is ignored (word-aligned registers).
