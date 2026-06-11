module spi_top (
    // APB
    input  wire        PCLK,
    input  wire        PRESETn,

    input  wire [3:0]  PADDR,
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [7:0]  PWDATA,
    output reg  [7:0]  PRDATA,
    output wire        PREADY,
    // Interrupt Signal
    output wire        spi_irq,

    // Pad Interface
    //SCK
    input  wire        sck_pad_i,
    output wire        sck_pad_o,
    output wire        sck_pad_oe,
    // MOSI
    input  wire        mosi_pad_i,
    output wire        mosi_pad_o,
    output wire        mosi_pad_oe,
    // MISO
    input  wire        miso_pad_i,
    output wire        miso_pad_o,
    output wire        miso_pad_oe,
    // SSN
    input  wire        ssn_pad_i,
    output wire        ssn_pad_o,
    output wire        ssn_pad_oe
);

// Interconnected Signals
// Regs
wire [7:0]  reg_SPICR1;
wire [7:0]  reg_SPICR2;
wire [7:0]  reg_SPIBR;
wire [7:0]  reg_SPIDR_TX;
wire [7:0]  RX_data;
wire        SPIDR_TX_valid;

// Reg Ctrl
wire        SPIF_set;
wire        SPTEF_set;
wire        MODF_set;

// MSTR/SLV Ctrl
wire        master_en;
wire        slave_en;

// Master
// Clock
wire        baud_en;
wire        sck_en;
wire        sck_rise_pulse;
wire        sck_fall_pulse;
wire        sck_out;
// Signals
wire [7:0]  master_RX_data;
wire        master_SPIF_set;
wire        master_SPTEF_set;
wire        master_MOSI_out;
wire        master_SSN_out;

// Slave
// Clock
wire        ssn_sync;
wire        slave_sck_rise;
wire        slave_sck_fall;
// Signals
wire [7:0]  slave_RX_data;
wire        slave_SPIF_set;
wire        slave_SPTEF_set;
wire        slave_MISO_out;

// Configurations
wire SPE     = reg_SPICR1[6];
wire MSTR    = reg_SPICR1[4];
wire CPOL    = reg_SPICR1[3];
wire CPHA    = reg_SPICR1[2];
wire SSOE    = reg_SPICR1[1];
wire LSBFE   = reg_SPICR1[0];

wire MODFEN  = reg_SPICR2[4];
wire BIDIROE = reg_SPICR2[3];
wire SPISWAI = reg_SPICR2[1];
wire SPC0    = reg_SPICR2[0];

// IO Muxing
// SCK
assign sck_pad_oe = SPE & MSTR;
assign sck_pad_o  = sck_out;

// MOSI
// SPC = 1  -->  check BIDIROE to determine transfer direction
assign mosi_pad_oe = SPE & (MSTR ? (SPC0 ? BIDIROE : 1'b1): 1'b0);
assign mosi_pad_o  = master_MOSI_out;

// MISO
assign miso_pad_oe = SPE & ((~MSTR & ~ssn_pad_i) ? (SPC0 ? BIDIROE : 1'b1) : 1'b0);
assign miso_pad_o  = slave_MISO_out;

// SSN
assign ssn_pad_oe = SPE & (MSTR & MODFEN & SSOE);
assign ssn_pad_o  = master_SSN_out;

// Reroute MIMO/SISO in bidirectional mode
// In Master mode, route MISO to MIMO(MOSI)
assign master_MIMO_in = (MSTR & SPC0) ? mosi_pad_i : miso_pad_i;
// In Slave mode, route MOSI to SISO(MISO)
assign slave_SISO_in  = (~MSTR & SPC0) ? miso_pad_i : mosi_pad_i;

// Detect Mode Fault
assign  MODF_set = MSTR & MODFEN & (~SSOE) & (~ssn_pad_i);

// Int Flag Muxing
assign SPIF_set  = MSTR ? master_SPIF_set   : slave_SPIF_set;
assign SPTEF_set = MSTR ? master_SPTEF_set  : slave_SPTEF_set;
assign RX_data   = MSTR ? master_RX_data    : slave_RX_data;

// Instantiations
spi_regs u_spi_regs (
    .PCLK           (PCLK),
    .PRESETn        (PRESETn),
    .PADDR          (PADDR),
    .PSEL           (PSEL),
    .PENABLE        (PENABLE),
    .PWRITE         (PWRITE),
    .PWDATA         (PWDATA),
    .PRDATA         (PRDATA),
    .PREADY         (PREADY),

    .reg_SPICR1     (reg_SPICR1),
    .reg_SPICR2     (reg_SPICR2),
    .reg_SPIBR      (reg_SPIBR),

    .SPIF_set       (SPIF_set),
    .SPTEF_set      (SPTEF_set),
    .MODF_set       (MODF_set),
    .RX_data        (RX_data),
    .reg_SPIDR_TX   (reg_SPIDR_TX),
    .SPIDR_TX_valid (SPIDR_TX_valid),
    .spi_irq        (spi_irq)
);

spi_fsm_top u_spi_fsm_top (
    .PCLK       (PCLK),
    .PRESETn    (PRESETn),

    .reg_SPICR1 (reg_SPICR1),
    .reg_SPICR2 (reg_SPICR2),
    .reg_SPIBR  (reg_SPIBR),

    .master_en  (master_en),
    .slave_en   (slave_en)
);

spi_baud_gen u_spi_baud_gen (
    .PCLK           (PCLK),
    .PRESETn        (PRESETn),

    .CPOL           (CPOL),
    .reg_SPIBR      (reg_SPIBR),

    .baud_en        (baud_en),
    .sck_en         (sck_en),

    .sck_rise_pulse (sck_rise_pulse),
    .sck_fall_pulse (sck_fall_pulse),

    .sck_out        (sck_out)
);

spi_master u_spi_master (
    .PCLK               (PCLK),
    .PRESETn            (PRESETn),

    .master_en          (master_en),

    .sck_rise_pulse     (sck_rise_pulse),
    .sck_fall_pulse     (sck_fall_pulse),

    .SPISWAI            (SPISWAI),
    .CPOL               (CPOL),
    .CPHA               (CPHA),
    .LSBFE              (LSBFE),
    .SPIDR_TX_valid     (SPIDR_TX_valid),
    .SPIDR_TX_buffer    (reg_SPIDR_TX),

    .baud_en            (baud_en),
    .sck_en             (sck_en),

    .SPIF_set           (master_SPIF_set),
    .SPTEF_set          (master_SPTEF_set),
    .RX_data            (master_RX_data),

    .MISO_in            (master_MIMO_in),   // Signal after rerouting
    .MOSI_out           (master_MOSI_out),
    .SSN                (master_SSN_out)
);

spi_cdc_sync u_spi_cdc_sync (
    .PCLK           (PCLK),
    .PRESETn        (PRESETn),

    .ext_sck        (sck_pad_i),
    .ext_ssn        (ssn_pad_i),

    .ssn_sync       (ssn_sync),
    .slave_sck_rise (slave_sck_rise),
    .slave_sck_fall (slave_sck_fall)
);

spi_slave u_spi_slave (
    .PCLK               (PCLK),
    .PRESETn            (PRESETn),

    .slave_en           (slave_en),

    .ssn_sync           (ssn_sync),
    .slave_sck_rise     (slave_sck_rise),
    .slave_sck_fall     (slave_sck_fall),

    .CPOL               (CPOL),
    .CPHA               (CPHA),
    .LSBFE              (LSBFE),
    .SPIDR_TX_buffer    (reg_SPIDR_TX),

    .SPIF_set           (slave_SPIF_set),
    .SPTEF_set          (slave_SPTEF_set),
    .RX_data            (slave_RX_data),

    .MOSI_in            (slave_SISO_in),    // // Signal after rerouting
    .MISO_out           (slave_MISO_out)
);


endmodule //spi_top
