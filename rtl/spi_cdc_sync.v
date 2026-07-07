module spi_cdc_sync (
    // APB
    input  wire        PCLK,
    input  wire        PRESETn,

    // External Asynchronous Signals
    input  wire        sck_pad_i,
    input  wire        ssn_pad_i,
    input  wire        mosi_pad_i,
    input  wire        miso_pad_i,

    // Synchronous Signals
    output wire        ssn_sync,
    output wire        ssn_falling,
    output wire        mosi_sync,
    output wire        miso_sync,
    // Slave Synchronous Clock Pulse
    output wire        slave_sck_rise,
    output wire        slave_sck_fall
);

// Sync sck
reg [2:0] sck_pipe;
reg [2:0] ssn_pipe;
reg [1:0] mosi_pipe;
reg [1:0] miso_pipe;

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        sck_pipe    <= 3'b000;
        ssn_pipe    <= 3'b111;
        mosi_pipe   <= 2'b00;
        miso_pipe   <= 2'b00;
    end else begin
        sck_pipe <= {sck_pipe[1:0], sck_pad_i};
        ssn_pipe <= {ssn_pipe[1:0], ssn_pad_i};
        mosi_pipe <= {mosi_pipe[0], mosi_pad_i};
        miso_pipe <= {miso_pipe[0], miso_pad_i};
    end
end

//SSN
assign ssn_sync = ssn_pipe[1];
assign ssn_falling = (ssn_pipe[2:1] == 2'b10);
//MOSI
assign mosi_sync = mosi_pipe[1];
//MISO
assign miso_sync = miso_pipe[1];
// Check SCK edge
assign slave_sck_rise = (sck_pipe[2:1] == 2'b01);
assign slave_sck_fall = (sck_pipe[2:1] == 2'b10);

endmodule //spi_cdc_sync
