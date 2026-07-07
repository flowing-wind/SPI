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
    input  wire [1:0]  FW,
    input  wire        SPIDR_TX_valid,
    input  wire [31:0] SPIDR_TX_buffer,

    // Ctrl Reg
    output reg         SPIF_set,
    output reg         SPTEF_set,
    output reg  [31:0] RX_data,

    // Ports
    input  wire        MOSI_in,
    output reg         MISO_out
);

// Generate Sample and Shift pulse
wire sample_pulse, shift_pulse;
assign sample_pulse = (CPOL ^ CPHA) ? slave_sck_fall : slave_sck_rise;
assign shift_pulse  = (CPOL ^ CPHA) ? slave_sck_rise : slave_sck_fall;

// Frame geometry
// FW: 00 = 8-bit, 01 = 16-bit, 10 = 32-bit, 11 = reserved (behaves as 8-bit)
reg [4:0] last_bit;     // frame width - 1
always @(*) begin
    case (FW)
        2'b01:   last_bit = 5'd15;
        2'b10:   last_bit = 5'd31;
        default: last_bit = 5'd7;
    endcase
end

// TX data left-justified for MSB-first shifting
reg [31:0] tx_msb_justified;
always @(*) begin
    case (FW)
        2'b01:   tx_msb_justified = {SPIDR_TX_buffer[15:0], 16'h0};
        2'b10:   tx_msb_justified = SPIDR_TX_buffer;
        default: tx_msb_justified = {SPIDR_TX_buffer[7:0], 24'h0};
    endcase
end
wire [31:0] tx_load      = LSBFE ? SPIDR_TX_buffer    : tx_msb_justified;
wire        tx_first_bit = LSBFE ? SPIDR_TX_buffer[0] : tx_msb_justified[31];

// Transfer
reg [4:0]  bit_cnt;
reg [31:0] shifter;
reg        tx_pending;
reg        spif_pending; // For CPHA=0 to wait the last edge

// Shift result and received word right-justified
wire [31:0] shifter_next = LSBFE ? {MOSI_in, shifter[31:1]} : {shifter[30:0], MOSI_in};
reg  [31:0] rx_word;
always @(*) begin
    case (FW)
        2'b01:   rx_word = LSBFE ? {16'h0, shifter_next[31:16]} : {16'h0, shifter_next[15:0]};
        2'b10:   rx_word = shifter_next;
        default: rx_word = LSBFE ? {24'h0, shifter_next[31:24]} : {24'h0, shifter_next[7:0]};
    endcase
end

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        SPIF_set     <= 1'b0;
        SPTEF_set    <= 1'b1;
        RX_data      <= 32'h0;
        bit_cnt      <= 5'd0;
        shifter      <= 32'h0;
        tx_pending   <= 1'b0;
        spif_pending <= 1'b0;
        MISO_out     <= 1'b0;
    end else if (!slave_en || ssn_sync) begin
        SPIF_set     <= 1'b0;
        SPTEF_set    <= 1'b0;
        bit_cnt      <= 5'd0;
        shifter      <= 32'h0;
        spif_pending <= 1'b0;
        MISO_out     <= 1'b0;
        if (SPIDR_TX_valid) begin
            tx_pending  <= 1'b1;
        end
    end else begin
        SPIF_set     <= 1'b0;
        SPTEF_set    <= 1'b0;
        if (SPIDR_TX_valid) begin
            tx_pending  <= 1'b1;
        end

        if (ssn_falling) begin
            shifter         <= tx_load;
            SPTEF_set       <= 1'b1;
            tx_pending      <= 1'b0;
            if (CPHA == 1'b0) begin
                MISO_out    <= tx_first_bit;
            end
        end

        if (shift_pulse) begin
            MISO_out    <= LSBFE ? shifter[0] : shifter[31];
            // CPHA = 0, the last shift edge
            if (CPHA == 1'b0 && spif_pending) begin
                SPIF_set     <= 1'b1;
                SPTEF_set    <= 1'b1;
                spif_pending <= 1'b0;
            end
        end

        if (sample_pulse) begin
            shifter  <= shifter_next;

            if (bit_cnt == last_bit) begin
                bit_cnt     <= 5'd0;
                RX_data     <= rx_word;
                // CPHA = 1, back to back transfer, the last edge, set SPIF and SPTEF
                if (CPHA == 1'b1) begin
                    SPIF_set     <= 1'b1;
                    SPTEF_set    <= 1'b1;
                    if (tx_pending) begin
                        shifter     <= tx_load;
                        tx_pending  <= 1'b0;
                    end
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
