module spi_cdc_sync (
    // APB
    input  wire        PCLK,
    input  wire        PRESETn,

    // External Asynchronous Signals
    input  wire        ext_sck,
    input  wire        ext_ssn,

    // Synchronous Signals
    output wire        ssn_sync,
    // Slave Synchronous Clock Pulse
    output wire        slave_sck_rise,
    output wire        slave_sck_fall
);

// Sync sck
reg [2:0] sck_pipe;
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        sck_pipe <= 3'b000;
    end else begin
        sck_pipe <= {sck_pipe[1:0], ext_sck};
    end
end
// Check edge
assign slave_sck_rise = (sck_pipe[2] == 1'b0) && (sck_pipe[1] == 1'b1);
assign slave_sck_fall = (sck_pipe[2] == 1'b1) && (sck_pipe[1] == 1'b0);

// Sync ssn
reg [1:0] ssn_pipe;
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        ssn_pipe <= 2'b11;
    end else begin
        ssn_pipe <= {ssn_pipe[0], ext_ssn};
    end
end
assign ssn_sync = ssn_pipe[1];

endmodule //spi_cdc_sync
