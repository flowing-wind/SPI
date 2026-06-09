module spi_slave (
    // APB
    input  wire        PCLK,
    input  wire        PRESETn,

    // CTRL
    input  wire        slave_en,

    // Synchronous External Signals
    input  wire        ssn_sync,
    input  wire        slave_sck_rise,
    input  wire        slave_sck_fall,

    // Config Signals
    input  wire        CPOL,
    input  wire        CPHA,
    input  wire        LSBFE,
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

// Detect SSN falling edge
reg ssn_sync_r;
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)
        ssn_sync_r <= 1'b1;
    else
        ssn_sync_r <= ssn_sync;
end
wire ssn_falling = (ssn_sync_r == 1'b1) && (ssn_sync == 1'b0);

// Transfer
reg [3:0] bit_cnt;
reg [7:0] rx_shifter, tx_shifter;
reg       tx_pending;
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        SPIF_set     <= 1'b0;
        SPTEF_set    <= 1'b1;
        RX_data      <= 8'h00;
        bit_cnt      <= 4'd0;
        rx_shifter   <= 8'h00;
        tx_shifter   <= 8'h00;
        tx_pending   <= 1'b0;
        MISO_out     <= 1'b0;
    end else if (!slave_en || ssn_sync) begin
        SPIF_set     <= 1'b0;
        bit_cnt      <= 4'd0;
        rx_shifter   <= 8'h00;
        tx_shifter   <= 8'h00;
        tx_pending   <= 1'b0;
        MISO_out     <= 1'b0;
    end else begin
        SPIF_set     <= 1'b0;
        SPTEF_set    <= 1'b0;

        if (CPHA == 1'b0 && ssn_falling) begin
            tx_shifter   <= SPIDR_TX_buffer;
            SPTEF_set    <= 1'b1;
            if (LSBFE) begin
                MISO_out    <= SPIDR_TX_buffer[0];
                tx_shifter  <= {1'b0, SPIDR_TX_buffer[7:1]};
            end else begin
                MISO_out    <= SPIDR_TX_buffer[7];
                tx_shifter  <= {SPIDR_TX_buffer[6:0], 1'b0};
            end
        end

        if (sample_pulse || shift_pulse) begin
            if (sample_pulse) begin
                if (LSBFE) begin
                    rx_shifter <= {MOSI_in, rx_shifter[7:1]};
                end else begin
                    rx_shifter <= {rx_shifter[6:0], MOSI_in};
                end
            end else if (shift_pulse) begin
                if (LSBFE) begin
                    MISO_out   <= tx_shifter[0];
                    tx_shifter <= {1'b0, tx_shifter[7:1]};
                end else begin
                    MISO_out   <= tx_shifter[7];
                    tx_shifter <= {tx_shifter[6:0], 1'b0};
                end
            end

            if (bit_cnt == 4'd15) begin
                bit_cnt     <= 4'd0;
                SPIF_set    <= 1'b1;
                tx_shifter  <= SPIDR_TX_buffer;
                if (CPHA == 1'b0) begin
                    RX_data <= rx_shifter;
                end else if (CPHA == 1'b1) begin
                    RX_data <= LSBFE ? {MOSI_in, rx_shifter[7:1]} : {rx_shifter[6:0], MOSI_in};
                end
            end else begin
                bit_cnt <= bit_cnt + 1'b1;
            end
        end


    end
end

endmodule //spi_slave
