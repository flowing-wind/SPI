module spi_slave (
    // APB
    input  wire        PCLK,
    input  wire        PRESETn,

    // CTRL
    input  wire        slave_en,

    // Synchronous External Signals
    input  wire        ssn_sync,
    input  wire        ssn_falling,
    input  wire        slave_sck_rise,
    input  wire        slave_sck_fall,

    // Config Signals
    input  wire        CPOL,
    input  wire        CPHA,
    input  wire        LSBFE,
    input  wire        SPIDR_TX_valid,
    input  wire [7:0]  SPIDR_TX_buffer,

    // Ctrl Reg
    output reg         SPIF_set,
    output reg         SPTEF_set,
    output reg  [7:0]  RX_data,

    // Ports
    input  wire        MOSI_in,
    output reg         MISO_out
);

// Generate Sample and Shift pulse
wire sample_pulse, shift_pulse;
assign sample_pulse = (CPOL ^ CPHA) ? slave_sck_fall : slave_sck_rise;
assign shift_pulse  = (CPOL ^ CPHA) ? slave_sck_rise : slave_sck_fall;

// Transfer
reg [2:0] bit_cnt;
reg [7:0] shifter;
reg       tx_pending;
reg       spif_pending; // For CPHA=0 to wait the last edge
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        SPIF_set     <= 1'b0;
        SPTEF_set    <= 1'b1;
        RX_data      <= 8'h00;
        bit_cnt      <= 3'd0;
        shifter      <= 8'h00;
        tx_pending   <= 1'b0;
        spif_pending <= 1'b0;
        MISO_out     <= 1'b0;
    end else if (!slave_en || ssn_sync) begin
        SPIF_set     <= 1'b0;
        bit_cnt      <= 3'd0;
        shifter      <= 8'h00;
        tx_pending   <= 1'b0;
        spif_pending <= 1'b0;
        MISO_out     <= 1'b0;
    end else begin
        SPIF_set     <= 1'b0;
        SPTEF_set    <= 1'b0;
        if (SPIDR_TX_valid) begin
            tx_pending  <= 1'b1;
        end

        if (ssn_falling) begin
            shifter         <= SPIDR_TX_buffer;
            SPTEF_set       <= 1'b1;
            tx_pending      <= 1'b0;
            if (CPHA == 1'b0) begin
                MISO_out    <= LSBFE ? SPIDR_TX_buffer[0] : SPIDR_TX_buffer[7];
            end
        end

        if (shift_pulse) begin
            MISO_out    <= LSBFE ? shifter[0] : shifter[7];
            // CPHA = 0, the last shift edge
            if (CPHA == 1'b0 && spif_pending) begin
                SPIF_set     <= 1'b1;
                SPTEF_set    <= 1'b1;
                spif_pending <= 1'b0;
            end
            // CPHA = 1, back to back transfer, receive the next tx_data
            if (CPHA == 1'b1 && bit_cnt == 3'd0 && tx_pending) begin
                MISO_out     <= LSBFE ? SPIDR_TX_buffer[0] : SPIDR_TX_buffer[7];
                shifter      <= SPIDR_TX_buffer;
                tx_pending   <= 1'b0;
            end
        end

        if (sample_pulse) begin
            shifter  <= LSBFE ? {MOSI_in, shifter[7:1]} : {shifter[6:0], MOSI_in};

            if (bit_cnt == 3'd7) begin
                bit_cnt     <= 3'd0;
                RX_data     <= LSBFE ? {MOSI_in, shifter[7:1]} : {shifter[6:0], MOSI_in};
                // CPHA = 1, back to back transfer, the last edge, set SPIF and SPTEF
                if (CPHA == 1'b1) begin
                    SPIF_set     <= 1'b1;
                    SPTEF_set    <= 1'b1;
                end else begin
                    // For CPHA = 0  and SSN still low (next cycle), tx send last data
                    spif_pending <= 1'b1;   // set SPIF and SPTEF next edge
                end
            end else begin
                bit_cnt <= bit_cnt + 1'b1;
            end
        end
    end
end

endmodule //spi_slave
