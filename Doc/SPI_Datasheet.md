# SPI IP Core — Datasheet

**Version:** 1.0
**Date:** 2026-07-07
**Bus interface:** AMBA APB (32-bit data)
**Reference:** Motorola/Freescale S12 SPI Block Guide V04.01 (S12SPIV4), extended with 8/16/32-bit frame width

---

## 1. Overview

The SPI IP core provides full-duplex, synchronous, serial communication between an
APB-based host system and external SPI devices. The programming model follows the
Motorola/Freescale S12 SPI (S12SPIV4) register set and flag semantics, with two
extensions:

- a **32-bit APB slave interface** (word-aligned register map), and
- a **selectable frame width** of 8, 16 or 32 bits, controlled by the SPIFW
  register placed at the address that is *reserved* in the original S12 memory map.

The core can operate as an SPI **master** or **slave**, supports all four SPI clock
modes (CPOL/CPHA), MSB- or LSB-first shifting, single-wire **bidirectional** mode
(MOMI/SISO), automatic **slave-select output**, **mode-fault** detection, and a
single combined **interrupt** output.

### 1.1 Features

- APB3 slave interface, 32-bit data bus, zero-wait-state (PREADY tied high)
- Master and slave modes of operation
- Programmable frame width: 8, 16 or 32 bits (SPIFW register)
- Programmable clock polarity (CPOL) and phase (CPHA) — all four SPI modes
- MSB-first or LSB-first transfer (LSBFE)
- Baud-rate generator with divisor 2 to 2048 (master mode only):
  `divisor = (SPPR+1) × 2^(SPR+1)`
- Double-buffered transmit and receive data register (SPIDR)
- Back-to-back transfers in master mode (CPHA = 1) with no inter-frame gap
- Automatic slave-select output (SSOE) with guaranteed leading/trailing/idle times
- Bidirectional single-wire mode (SPC0/BIDIROE): MOMI (master) / SISO (slave)
- Mode-fault (MODF) detection with automatic master-to-slave demotion
- Status flags SPIF, SPTEF, MODF with S12-style read-then-access clearing protocol
- Single interrupt request output, maskable via SPIE / SPTIE
- Low-power behavior: SPE = 0 forces an idle, flag-cleared state; SPISWAI freezes
  a master transfer
- Two-stage (data) / three-stage (clock, select) synchronizers on all pad inputs;
  the whole core runs on the single PCLK domain

### 1.2 Deliverables

| Directory | Content |
|-----------|---------|
| `rtl/` | Synthesizable Verilog-2001 RTL (7 files, top: `spi_top`) |
| `tb/tb_spi.sv` | Self-checking functional testbench (Icarus Verilog compatible) |
| `Doc/` | This datasheet and the S12SPIV4 reference manual |

---

## 2. Architecture

### 2.1 Block Diagram

```
             ┌────────────────────────────────────────────────────────────┐
             │                          spi_top                           │
             │                                                            │
  APB ───────┼──► spi_regs ──────── reg_SPICR1/2, SPIBR, SPIFW ──┬──►     │
  (32-bit)   │      │  ▲                                         │        │
             │      │  └── SPIF/SPTEF/MODF set, RX_data          │        │
  spi_irq ◄──┼──────┤                                            ▼        │
             │      │                                      spi_fsm_top    │
             │      │                                     (mode control,  │
             │      │                                      cfg-change     │
             │      │                                      abort)         │
             │      │                                        │   │        │
             │      ▼                                 master_en  slave_en │
             │  SPIDR TX buffer ──────────────┬──────────┐   │   │        │
             │                                ▼          ▼   ▼   ▼        │
             │                          spi_master     spi_slave          │
             │                            │  ▲            ▲  │            │
             │              baud_en/sck_en│  │MISO    MOSI│  │MISO        │
             │                            ▼  │            │  ▼            │
             │                       spi_baud_gen    spi_cdc_sync         │
             │                            │               ▲ ▲ ▲ ▲         │
             │                        SCK out             │ │ │ │         │
             │                                            │ │ │ │         │
             └───────────┬────────────┬───────────────────┼─┼─┼─┼─────────┘
                         ▼            ▼                   │ │ │ │
                     pad mux (oe/o per pin)          sck ssn mosi miso (pad in)
```

### 2.2 Module Descriptions

| Module | File | Function |
|--------|------|----------|
| `spi_top` | `rtl/spi_top.v` | Top level: pad muxing, bidirectional rerouting, mode-fault detection, flag muxing |
| `spi_regs` | `rtl/spi_regs.v` | APB slave, register file, flag set/clear protocol, RX double buffering, interrupt generation |
| `spi_fsm_top` | `rtl/spi_fsm_top.v` | Master/slave mode enable control; aborts transfers when configuration changes |
| `spi_master` | `rtl/spi_master.v` | Master transfer FSM, 32-bit shifter, SS output timing (t_L / t_T / t_I) |
| `spi_slave` | `rtl/spi_slave.v` | Slave transfer logic, 32-bit shifter, SS-qualified shifting |
| `spi_baud_gen` | `rtl/spi_baud_gen.v` | Baud-rate divider, SCK generation and internal rise/fall timing pulses |
| `spi_cdc_sync` | `rtl/spi_cdc_sync.v` | Input synchronizers, SCK edge detection, SS falling-edge detection |

### 2.3 Clocking and Reset

- Single clock domain: everything runs on **PCLK**.
- Asynchronous active-low reset **PRESETn** (asserted asynchronously, released
  synchronously by the system).
- In slave mode, the external SCK is *not* used as a clock: it is synchronized
  into the PCLK domain and its edges are detected there. See §6.2 for the
  resulting maximum slave SCK frequency.

---

## 3. Signal Description

### 3.1 APB Interface

| Signal | Dir | Width | Description |
|--------|-----|-------|-------------|
| `PCLK` | in | 1 | Bus clock; single clock of the core |
| `PRESETn` | in | 1 | Asynchronous active-low reset |
| `PADDR` | in | 5 | Byte address, word aligned (bits [1:0] ignored) |
| `PSEL` | in | 1 | Peripheral select |
| `PENABLE` | in | 1 | Access phase enable |
| `PWRITE` | in | 1 | 1 = write, 0 = read |
| `PWDATA` | in | 32 | Write data |
| `PRDATA` | out | 32 | Read data |
| `PREADY` | out | 1 | Always 1 (zero wait states) |
| `spi_irq` | out | 1 | Interrupt request, active high, level |

### 3.2 Pad Interface

Each SPI pin is exported as an input / output / output-enable triple, intended
for connection to a tri-state or bidirectional pad cell
(`pad = oe ? o : Hi-Z`, `i = pad`).

| Signal group | Pins | Function (master) | Function (slave) |
|--------------|------|--------------------|-------------------|
| `sck_pad_i/o/oe` | SCK | Serial clock output | Serial clock input |
| `mosi_pad_i/o/oe` | MOSI | Data output (MOMI in bidirectional mode) | Data input (unused in bidirectional mode) |
| `miso_pad_i/o/oe` | MISO | Data input (unused in bidirectional mode) | Data output (SISO in bidirectional mode) |
| `ssn_pad_i/o/oe` | SS | Mode-fault input (MODFEN=1, SSOE=0), slave-select output (MODFEN=1, SSOE=1), unused otherwise | Slave-select input (always) |

All output enables are gated with SPE and forced inactive while MODF is set.

---

## 4. Register Map

Base address is assigned at SoC integration. All registers are 32-bit APB words;
unimplemented bits read zero and writes to them are ignored.

| Offset | Name | Access | Reset | Description |
|--------|--------|--------|------------|--------------------------------|
| 0x00 | SPICR1 | R/W | 0x0000_0004 | Control register 1 |
| 0x04 | SPICR2 | R/W¹ | 0x0000_0000 | Control register 2 |
| 0x08 | SPIBR | R/W¹ | 0x0000_0030 | Baud rate register |
| 0x0C | SPISR | R | 0x0000_0020 | Status register (writes ignored) |
| 0x10 | SPIFW | R/W | 0x0000_0000 | Frame width register² |
| 0x14 | SPIDR | R/W | 0x0000_0000 | Data register (TX on write, RX on read) |
| 0x18 | — | — | 0x0000_0000 | Reserved (reads zero) |
| 0x1C | — | — | 0x0000_0000 | Reserved (reads zero) |

¹ Reserved bits are non-writable.
² Location `$4` is *reserved* in the S12SPIV4 memory map; this core uses it for
the frame-width extension.

### 4.1 SPICR1 — SPI Control Register 1 (offset 0x00)

| Bit | Name | Reset | Description |
|-----|-------|-------|-------------|
| 7 | SPIE | 0 | SPI interrupt enable: 1 = request interrupt when SPIF or MODF is set |
| 6 | SPE | 0 | SPI system enable. 0 = core disabled and forced idle; status flags reset |
| 5 | SPTIE | 0 | Transmit interrupt enable: 1 = request interrupt when SPTEF is set |
| 4 | MSTR | 0 | 1 = master mode, 0 = slave mode. Cleared automatically on mode fault |
| 3 | CPOL | 0 | Clock polarity: 0 = idle low (active-high clock), 1 = idle high |
| 2 | CPHA | 1 | Clock phase: 0 = sample on odd SCK edges, 1 = sample on even SCK edges |
| 1 | SSOE | 0 | Slave-select output enable (effective with MODFEN = 1, master mode; see Table 4-A) |
| 0 | LSBFE | 0 | 1 = LSB transmitted first. Data in SPIDR is always right-justified regardless of LSBFE |

**Table 4-A — SS pin configuration (master mode)**

| MODFEN | SSOE | Master mode SS pin |
|--------|------|---------------------|
| 0 | 0 | SS not used by SPI |
| 0 | 1 | SS not used by SPI |
| 1 | 0 | SS input with MODF feature |
| 1 | 1 | SS is slave-select output |

In slave mode SS is always the slave-select input.

In master mode, changing MSTR, CPOL, CPHA, SSOE or LSBFE while a transfer is in
progress **aborts the transfer** and forces the core into the idle state (the
remote slave cannot detect this — software must re-synchronize it). In slave
mode, changing these bits during a transfer corrupts the transfer and must be
avoided.

### 4.2 SPICR2 — SPI Control Register 2 (offset 0x04)

| Bit | Name | Reset | Description |
|-----|-------|-------|-------------|
| 7:5 | — | 0 | Reserved, read zero |
| 4 | MODFEN | 0 | Mode-fault enable. 0 = SS pin not used by master; see Table 4-A |
| 3 | BIDIROE | 0 | Bidirectional output enable: drives the MOMI (master) / SISO (slave) pin when SPC0 = 1 |
| 2 | — | 0 | Reserved, read zero |
| 1 | SPISWAI | 0 | 1 = freeze a master transfer in progress (wait-mode power saving; see §6.4) |
| 0 | SPC0 | 0 | 1 = bidirectional (single data wire) pin configuration; see Table 4-B |

**Table 4-B — Bidirectional pin configuration**

| Mode | SPC0 | BIDIROE | MISO pin | MOSI pin |
|------|------|---------|----------|----------|
| Master normal | 0 | x | master in | master out |
| Master bidirectional | 1 | 0 | not used | master in (MOMI) |
| Master bidirectional | 1 | 1 | not used | master I/O (MOMI) |
| Slave normal | 0 | x | slave out | slave in |
| Slave bidirectional | 1 | 0 | slave in (SISO) | not used |
| Slave bidirectional | 1 | 1 | slave I/O (SISO) | not used |

### 4.3 SPIBR — SPI Baud Rate Register (offset 0x08)

| Bit | Name | Reset | Description |
|-----|-------|-------|-------------|
| 7 | — | 0 | Reserved, read zero |
| 6:4 | SPPR[2:0] | 3 | Baud-rate preselection |
| 3 | — | 0 | Reserved, read zero |
| 2:0 | SPR[2:0] | 0 | Baud-rate selection |

```
BaudRateDivisor = (SPPR + 1) × 2^(SPR + 1)          (range 2 … 2048)
SCK frequency   = f_PCLK / BaudRateDivisor
```

The reset value 0x30 gives a divisor of 8. The baud-rate generator only runs in
master mode while a transfer is active. In slave mode SPIBR is ignored.

Example divisors (f_PCLK = 100 MHz):

| SPPR | SPR | Divisor | SCK |
|------|-----|---------|----------|
| 0 | 0 | 2 | 50.0 MHz |
| 0 | 1 | 4 | 25.0 MHz |
| 0 | 2 | 8 | 12.5 MHz |
| 3 | 0 | 8 | 12.5 MHz |
| 3 | 1 | 16 | 6.25 MHz |
| 4 | 2 | 40 | 2.5 MHz |
| 7 | 7 | 2048 | 48.8 kHz |

### 4.4 SPISR — SPI Status Register (offset 0x0C, read-only)

| Bit | Name | Reset | Description |
|-----|-------|-------|-------------|
| 7 | SPIF | 0 | Interrupt flag: a received frame has been copied into SPIDR. Cleared by reading SPISR (with SPIF = 1) followed by reading SPIDR |
| 6 | — | 0 | Reserved |
| 5 | SPTEF | 1 | Transmit-empty flag: the TX buffer can accept data. Cleared by reading SPISR (with SPTEF = 1) followed by writing SPIDR |
| 4 | MODF | 0 | Mode-fault flag. Cleared by reading SPISR (with MODF = 1) followed by writing SPICR1 |
| 3:0 | — | 0 | Reserved |

Writes to SPISR are ignored. Clearing SPE resets SPISR to 0x20.

### 4.5 SPIFW — SPI Frame Width Register (offset 0x10) — *extension*

| Bit | Name | Reset | Description |
|-----|-------|-------|-------------|
| 31:2 | — | 0 | Reserved, read zero |
| 1:0 | FW | 0 | Frame width: `00` = 8-bit, `01` = 16-bit, `10` = 32-bit, `11` = reserved (behaves as 8-bit) |

FW applies to both master and slave modes. **Master and slave must be
configured with the same frame width.** Changing FW in master mode aborts a
transfer in progress. Data in SPIDR is always right-justified: an 8-bit frame
occupies SPIDR[7:0], a 16-bit frame SPIDR[15:0], a 32-bit frame SPIDR[31:0].
Unused upper SPIDR bits are ignored on write and read zero on read.

### 4.6 SPIDR — SPI Data Register (offset 0x14)

| Bit | Name | Reset | Description |
|-----|-------|-------|-------------|
| 31:0 | DATA | 0 | Write: transmit data (queued in the TX buffer). Read: last received frame |

SPIDR is double-buffered in both directions:

- **Write path.** A write to SPIDR is only accepted after SPISR has been read
  with SPTEF = 1 (S12 handshake). A write without this handshake is **ignored**.
  In master mode an accepted write starts a transfer (or queues a frame for a
  back-to-back transfer when CPHA = 1). In slave mode the queued frame is loaded
  into the shifter when SS falls.
- **Read path.** Received frames are copied from the shift register into the RX
  buffer when SPIF is clear. If SPIF is still set when another frame completes,
  the new frame is held pending and transferred to SPIDR when the CPU reads the
  previous one (SPIF then remains set). Reading SPIDR after reset returns zero.

---

## 5. Functional Description

### 5.1 Master Mode

Master mode is selected with MSTR = 1 (and SPE = 1). Only a master initiates
transfers. A transfer starts when a frame is written into SPIDR using the
SPTEF handshake:

1. SS output (if enabled) is driven low.
2. After half an SCK period (t_L, minimum leading time) SCK starts.
3. `2 × frame-width` SCK edges are generated; data is shifted out on MOSI and
   sampled from MISO according to CPOL/CPHA/LSBFE.
4. After the last edge, SPIF is set half an SCK period later (t_T, minimum
   trailing time), SS returns high, and a minimum idle time t_I (half SCK
   period) is respected before the next frame.
5. With CPHA = 1, if a new frame is already queued (SPTEF handshake completed
   during the running transfer), it is transmitted **back-to-back** with no
   trailing/idle gap and SS stays low.

### 5.2 Slave Mode

Slave mode is selected with MSTR = 0. SCK is an input; SPIBR is ignored.

- SS must be low before and during the whole transfer; SS high forces the slave
  shifter into idle and tri-states the data output.
- With CPHA = 0 the first queued data bit is driven on the data output as soon
  as SS falls; SS must be deasserted between successive frames (at least half
  an SCK period).
- With CPHA = 1 the first edge is used to output the first bit; SS may stay low
  between frames (tie-low operation supported). If no new frame was queued for
  a back-to-back transfer, the previously received data is shifted back out.
- Received frames set SPIF via the same double-buffered path as master mode;
  writes to SPIDR queue TX data that is loaded when SS next falls (or, with
  CPHA = 1 back-to-back, at the frame boundary).

### 5.3 Transfer Formats

The serial data line changes on "shift" edges and is captured on "sample"
edges. With CPHA = 0, sampling occurs on odd SCK edges (1, 3, 5, …); with
CPHA = 1, on even edges (2, 4, 6, …). CPOL selects the SCK idle level. The four
combinations are the standard SPI modes 0–3:

| SPI mode | CPOL | CPHA | SCK idle | Sample edge |
|----------|------|------|----------|-------------|
| 0 | 0 | 0 | low | rising |
| 1 | 0 | 1 | low | falling |
| 2 | 1 | 0 | high | falling |
| 3 | 1 | 1 | high | rising |

A frame is 8, 16 or 32 bits (SPIFW). With LSBFE = 0 the MSB (bit width-1) is
transferred first; with LSBFE = 1 the LSB (bit 0) is transferred first. In both
cases software reads and writes right-justified data in SPIDR.

### 5.4 Mode Fault (MODF)

When the core is a master with MODFEN = 1 and SSOE = 0, the SS pin is an input:
if it is driven low by another master, a mode fault is raised. The core then:

- sets MODF in SPISR (and requests an interrupt if SPIE = 1),
- **clears MSTR automatically** (demotes itself to slave mode),
- disables all pad output enables (SCK, MOSI, MISO become inputs),
- in bidirectional mode (SPC0 = 1), **clears the BIDIROE bit** (MOMI output
  enable) automatically,
- aborts a transfer in progress.

MODF is cleared by reading SPISR (with MODF = 1) followed by a write to SPICR1.
Mode fault detection is disabled when the SS output feature is enabled
(MODFEN = 1, SSOE = 1), when MODFEN = 0, and always in slave mode.

### 5.5 Interrupts

`spi_irq` is a level interrupt, asserted while SPE = 1 and:

```
spi_irq = (SPIE & (SPIF | MODF)) | (SPTIE & SPTEF)
```

Clearing the corresponding flag (see §4.4) deasserts the request.

### 5.6 Configuration-Change Abort

A dedicated control FSM (`spi_fsm_top`) monitors the configuration bits
(SPICR1[4:0], MODFEN, SPC0, BIDIROE-with-SPC0, SPPR, SPR, FW). In master mode,
any change forces the transfer logic through idle, aborting a transfer in
progress — matching the S12 note that configuration changes abort transmission.
Always reconfigure the core only when idle, and re-synchronize the remote slave
after an aborted transfer.

---

## 6. Design Notes and Limitations

### 6.1 Single Clock Domain / Input Synchronization

All pad inputs pass through `spi_cdc_sync`: MOSI/MISO use 2-stage synchronizers,
SCK and SS use 3-stage pipes with edge detection. In slave mode, shifting is
performed in the PCLK domain on detected SCK edges.

### 6.2 Maximum SCK Frequencies

- **Master mode:** divisor ≥ 2, so f_SCK ≤ f_PCLK / 2. For a remote slave of
  this same IP, respect the slave limit below.
- **Slave mode:** because SCK edges are detected via synchronizers, each half
  period of the external SCK must exceed the synchronization latency. Keep
  **f_SCK ≤ f_PCLK / 6** (recommended f_PCLK/8) in slave mode.

### 6.3 Deviations from the S12SPIV4 Reference

| # | Item | This core |
|---|------|-----------|
| 1 | Bus interface | 32-bit APB, word-aligned map (original: 8-bit CPU bus, byte map) |
| 2 | Frame width | 8/16/32-bit via SPIFW at reserved offset `$4` (original: fixed 8-bit) |
| 3 | Wait mode | There is no CPU in the system, hence no wait-mode input. SPISWAI = 1 directly freezes a master transfer; it resumes when SPISWAI is cleared. Slave operation is unaffected by SPISWAI |
| 4 | Stop mode | Not implemented inside the core; gate PCLK at SoC level if needed. Register state is retained as long as PCLK/PRESETn are maintained |
| 5 | RX overrun timing | If SPIF is not serviced, the S12 invalidates the pending frame at the *start* of the next-next transfer. This core keeps the pending frame valid until it is overwritten at the *end* of the following transfer (more forgiving: the frame can still be recovered while the next transfer is in flight; no data is ever silently reordered) |
| 6 | Port/pad control | Pull-ups, drive strength and pad routing are SoC-level and not part of the core |
| 7 | Electrical timing | See your SoC guide; §6.2 gives the functional limits |

### 6.4 Low-Power Behavior

- **SPE = 0:** clocks to the transfer logic are gated by the enable FSM, status
  flags are reset, pads are released. Registers remain accessible.
- **SPISWAI = 1 (master):** the transfer FSM freezes in place (SCK stops) and
  resumes without data loss when SPISWAI is cleared.

---

## 7. Programming Guide

All examples use `BASE` as the APB base address and the offsets of §4.
"Read SPISR" means an APB read of `BASE+0x0C`.

### 7.1 Initialization — master, mode 0, 16-bit frames, SCK = PCLK/16

```
write BASE+0x08 (SPIBR)  = 0x0000_0031   // SPPR=3, SPR=1 -> divisor 16
write BASE+0x10 (SPIFW)  = 0x0000_0001   // 16-bit frames
write BASE+0x04 (SPICR2) = 0x0000_0010   // MODFEN=1 (with SSOE -> SS output)
write BASE+0x00 (SPICR1) = 0x0000_0052   // SPE=1, MSTR=1, SSOE=1, mode 0
```

### 7.2 Initialization — slave, mode 3, 32-bit frames

```
write BASE+0x10 (SPIFW)  = 0x0000_0002   // 32-bit frames
write BASE+0x04 (SPICR2) = 0x0000_0000
write BASE+0x00 (SPICR1) = 0x0000_004C   // SPE=1, MSTR=0, CPOL=1, CPHA=1
```

### 7.3 Transmit + Receive one frame (polling)

```
// --- send ---
do { s = read BASE+0x0C } while (!(s & 0x20));   // wait SPTEF=1 (this read arms the handshake)
write BASE+0x14 = tx_data;                        // accepted; master starts the frame

// --- receive ---
do { s = read BASE+0x0C } while (!(s & 0x80));   // wait SPIF=1 (this read arms the clear)
rx_data = read BASE+0x14;                         // returns the frame, clears SPIF
```

> A write to SPIDR **without** a preceding SPISR read that returned SPTEF = 1 is
> ignored. Likewise SPIF is only cleared by the SPISR-read → SPIDR-read sequence.

### 7.4 Back-to-back transmission (master, CPHA = 1)

```
poll SPISR until SPTEF=1
write SPIDR = frame0                 // transfer 0 starts
poll SPISR until SPTEF=1             // buffer empty again while frame0 shifts
write SPIDR = frame1                 // frame1 queued -> sent with no gap, SS stays low
...
```

### 7.5 Mode-fault handling

```
irq handler:
    s = read BASE+0x0C               // SPISR, observe MODF=1 (read arms the clear)
    write BASE+0x00 = SPICR1_value   // clears MODF; note MSTR was auto-cleared
    // decide whether to re-arbitrate for the bus and set MSTR again
```

### 7.6 APB transaction examples

Zero-wait-state APB3 write (`PREADY` is always high):

```
        T0          T1          T2
PCLK   ─┐_┌─┐_┌─┐_┌─┐_┌─┐_┌─
PADDR   ──< 0x14      >──────
PWDATA  ──< 0x0000A5C3>──────
PWRITE  ──<    1      >──────
PSEL    __/‾‾‾‾‾‾‾‾‾‾‾\______
PENABLE ______/‾‾‾‾‾‾‾\______      (setup phase T0-T1, access phase T1-T2)
```

Read is identical with PWRITE = 0; PRDATA is valid during the access phase.

Complete 8-bit loop-back example (master sends 0xA5, receives slave's frame):

| # | Operation | Address | Data | Comment |
|---|-----------|---------|--------|---------|
| 1 | write | BASE+0x08 | 0x31 | divisor 16 |
| 2 | write | BASE+0x10 | 0x00 | 8-bit frames |
| 3 | write | BASE+0x04 | 0x10 | MODFEN=1 |
| 4 | write | BASE+0x00 | 0x52 | SPE, MSTR, SSOE |
| 5 | read | BASE+0x0C | 0x20 | SPTEF=1 (arms TX) |
| 6 | write | BASE+0x14 | 0xA5 | transfer starts |
| 7 | read | BASE+0x0C | 0x20 | poll: SPIF still 0 |
| 8 | read | BASE+0x0C | 0xA0 | SPIF=1, SPTEF=1 |
| 9 | read | BASE+0x14 | 0x3C | received frame; SPIF cleared |

---

## 8. Verification

- `tb/tb_spi.sv` — self-checking testbench connecting two `spi_top` instances
  (master + slave) pad-to-pad. Covers: register reset/access, all four SPI
  modes × 8/16/32-bit frames, LSB-first, the SPTEF/SPIF handshakes, rejected
  SPIDR writes, back-to-back CPHA = 1 transfers, bidirectional mode, and mode
  fault including BIDIROE auto-clear (80 checks).

  ```
  cd tb
  iverilog -g2012 -o spi_tb.vvp ../rtl/*.v tb_spi.sv
  vvp spi_tb.vvp
  ```

  Simulation outputs (`spi_tb.vvp`, `tb_spi.vcd` waveform dump) are produced
  inside `tb/`.

---

## 9. Revision History

| Version | Date | Changes |
|---------|------------|---------|
| 1.0 | 2026-07-07 | 32-bit APB interface; 8/16/32-bit frame width (SPIFW); CPOL=1 master clocking fix; reserved-bit write masking; SPISWAI flag-pulse fix; slave TX queueing while deselected; BIDIROE auto-clear on mode fault; initial datasheet |
