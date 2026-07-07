module spi_master (
    // APB
    input  wire        PCLK,
    input  wire        PRESETn,

    // CTRL
    input  wire        master_en,

    // Clock
    input  wire        sck_rise_pulse,
    input  wire        sck_fall_pulse,

    // Config Signals
    input  wire        SPISWAI,
    input  wire        CPOL,
    input  wire        CPHA,
    input  wire        LSBFE,
    input  wire [1:0]  FW,
    input  wire        SPIDR_TX_valid,
    input  wire [31:0] SPIDR_TX_buffer,

    // Ctrl baud_gen
    output reg         baud_en,
    output reg         sck_en,

    // Ctrl Reg
    output reg         SPIF_set,
    output reg         SPTEF_set,
    output reg  [31:0] RX_data,

    // Ports
    input  wire        MISO_in,
    output reg         MOSI_out,
    output reg         SSN
);

// Generate Sample and Shift pulse
wire sample_pulse, shift_pulse;
assign sample_pulse = (CPOL ^ CPHA) ? sck_fall_pulse : sck_rise_pulse;
assign shift_pulse  = (CPOL ^ CPHA) ? sck_rise_pulse : sck_fall_pulse;

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

// Master FSM
reg [1:0] state_master;
localparam MSTR_IDLE        = 2'b00;
localparam MSTR_Shift_Data  = 2'b01;
localparam MSTR_TAIL_1      = 2'b10;    // t_T
localparam MSTR_TAIL_2      = 2'b11;    // t_I
reg [4:0]  bit_cnt;
reg [31:0] shifter;
reg        tx_pending;

// Shift result and received word right-justified
wire [31:0] shifter_next = LSBFE ? {MISO_in, shifter[31:1]} : {shifter[30:0], MISO_in};
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
        baud_en      <= 1'b0;
        sck_en       <= 1'b0;
        SPIF_set     <= 1'b0;
        SPTEF_set    <= 1'b1;
        RX_data      <= 32'h0;
        bit_cnt      <= 5'd0;
        shifter      <= 32'h0;
        tx_pending   <= 1'b0;
        MOSI_out     <= 1'b0;
        SSN          <= 1'b1;
        state_master <= MSTR_IDLE;
    end else if (!master_en) begin
        baud_en      <= 1'b0;
        sck_en       <= 1'b0;
        SPIF_set     <= 1'b0;
        SPTEF_set    <= 1'b0;
        bit_cnt      <= 5'd0;
        shifter      <= 32'h0;
        tx_pending   <= 1'b0;
        MOSI_out     <= 1'b0;
        SSN          <= 1'b1;
        state_master <= MSTR_IDLE;
    end else if (SPISWAI) begin
        // Freeze the transfer, but do not hold the single-cycle flag pulses
        SPIF_set     <= 1'b0;
        SPTEF_set    <= 1'b0;
    end else begin
        // Latch the Signal whenever APB writes to SPIDR
        if (SPIDR_TX_valid) begin
            tx_pending   <= 1'b1;
        end

        SPIF_set  <= 1'b0;
        SPTEF_set <= 1'b0;

        case (state_master)
            MSTR_IDLE: begin
                SPIF_set     <= 1'b0;
                bit_cnt      <= 5'd0;
                if (tx_pending || SPIDR_TX_valid) begin
                    baud_en         <= 1'b1;
                    sck_en          <= 1'b1;
                    SPTEF_set       <= 1'b1;
                    SSN             <= 1'b0;
                    shifter         <= tx_load;
                    tx_pending      <= 1'b0;    // clear pending flag
                    state_master    <= MSTR_Shift_Data;
                    if (CPHA == 1'b0) begin     // Give data before the first pulse
                        MOSI_out    <= tx_first_bit;
                    end
                end
            end

            MSTR_Shift_Data: begin
                if (shift_pulse) begin
                    // Detect if it is the last edge for CPHA = 0
                    if (CPHA == 1'b0 && bit_cnt == 5'd0) begin
                        baud_en      <= 1'b1;   // Still counting
                        sck_en       <= 1'b0;   // But stop sck output
                        state_master <= MSTR_TAIL_1;
                    end else begin
                        MOSI_out     <= LSBFE ? shifter[0] : shifter[31];
                    end
                end

                if (sample_pulse) begin
                    shifter  <= shifter_next;

                    if (bit_cnt == last_bit) begin
                        // Back to Back transfers, works when CPHA = 1
                        if (CPHA == 1'b1) begin
                            if (tx_pending || SPIDR_TX_valid) begin
                                bit_cnt      <= 5'd0;
                                SPIF_set     <= 1'b1;
                                SPTEF_set    <= 1'b1;
                                tx_pending   <= 1'b0;
                                shifter      <= tx_load;
                                state_master <= MSTR_Shift_Data;
                                // copy to rx_buffer
                                RX_data      <= rx_word;
                            end else begin
                                baud_en      <= 1'b1;   // Still counting
                                sck_en       <= 1'b0;   // But stop sck output
                                state_master <= MSTR_TAIL_1;
                            end
                        end else begin
                            // For CPHA = 0, it needs the last shift edge
                            bit_cnt <= 5'd0;
                        end
                    end else begin
                        bit_cnt <= bit_cnt + 1'b1;
                    end
                end
            end

            MSTR_TAIL_1: begin
                MOSI_out     <= 1'b0;
                if (sck_rise_pulse || sck_fall_pulse) begin
                    SSN          <= 1'b1;
                    SPIF_set     <= 1'b1;
                    // Shifting already completed; re-justify the captured frame
                    case (FW)
                        2'b01:   RX_data <= LSBFE ? {16'h0, shifter[31:16]} : {16'h0, shifter[15:0]};
                        2'b10:   RX_data <= shifter;
                        default: RX_data <= LSBFE ? {24'h0, shifter[31:24]} : {24'h0, shifter[7:0]};
                    endcase
                    state_master <= MSTR_TAIL_2;
                end
            end

            MSTR_TAIL_2: begin      // minimum SSN high time  -->  Half SCK Cycle
                if (sck_rise_pulse || sck_fall_pulse) begin
                    baud_en      <= 1'b0;
                    state_master <= MSTR_IDLE;
                end
            end

            default: state_master <= MSTR_IDLE;
        endcase
    end
end

endmodule //spi_master
