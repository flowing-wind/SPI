module spi_fsm (
    // APB
    input  wire        PCLK,
    input  wire        PRESETn,

    // Input from spi_regs
    input  wire [7:0]  reg_SPICR1,
    input  wire [7:0]  reg_SPICR2,
    input  wire [7:0]  reg_SPIDR_TX,
    input  wire        reg_SPIDR_TX_valid,
    // Output for spi_regs
    output reg         fsm_SPIF_set,
    output reg         fsm_SPTEF_set,
    output reg         fsm_MODF_set,
    output reg  [7:0]  fsm_RX_data,

    // Input from spi_baud_gen
    input  wire        sck_rise_pulse,
    input  wire        sck_fall_pulse,
    // Output for spi_baud_gen
    output reg         fsm_active,

    // Input from spi_cdc_sync
    input  wire        ssn_sync,
    input  wire        slave_sck_rise,
    input  wire        slave_sck_fall,

    // Ext Ports
    // SSN
    input  wire        ext_ssn_in,
    output reg         ext_ssn_out,
    output reg         ext_ssn_oe, 
    // MOSI
    input  wire        ext_mosi_in,
    output reg         ext_mosi_out,
    output reg         ext_mosi_oe,
    // MISO
    input  wire        ext_miso_in,
    output reg         ext_miso_out,
    output reg         ext_miso_oe
);

// Signals




endmodule //spi_fsm
