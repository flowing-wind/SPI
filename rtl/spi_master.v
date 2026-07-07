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
    input  wire        SPIDR_TX_valid,
    input  wire [7:0]  SPIDR_TX_buffer,

    // Ctrl baud_gen
    output reg         baud_en,
    output reg         sck_en,

    // Ctrl Reg
    output reg         SPIF_set,
    output reg         SPTEF_set,
    output reg  [7:0]  RX_data,

    // Ports
    input  wire        MISO_in,
    output reg         MOSI_out,
    output reg         SSN
);

// Generate Sample and Shift pulse
wire sample_pulse, shift_pulse;
assign sample_pulse = (CPOL ^ CPHA) ? sck_fall_pulse : sck_rise_pulse;
assign shift_pulse  = (CPOL ^ CPHA) ? sck_rise_pulse : sck_fall_pulse;

// Master FSM
reg [1:0] state_master;
localparam MSTR_IDLE        = 2'b00;
localparam MSTR_Shift_Data  = 2'b01;
localparam MSTR_TAIL_1      = 2'b10;    // t_T
localparam MSTR_TAIL_2      = 2'b11;    // t_I
reg [2:0] bit_cnt;
reg [7:0] shifter;
reg       tx_pending;
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        baud_en      <= 1'b0;
        sck_en       <= 1'b0;
        SPIF_set     <= 1'b0;
        SPTEF_set    <= 1'b1;
        RX_data      <= 8'h00;
        bit_cnt      <= 3'd0;
        shifter      <= 8'h00;
        tx_pending   <= 1'b0;
        MOSI_out     <= 1'b0;
        SSN          <= 1'b1;
        state_master <= MSTR_IDLE;
    end else if (!master_en) begin
        baud_en      <= 1'b0;
        sck_en       <= 1'b0;
        SPIF_set     <= 1'b0;
        SPTEF_set    <= 1'b0;
        bit_cnt      <= 3'd0;
        shifter      <= 8'h00;
        tx_pending   <= 1'b0;
        MOSI_out     <= 1'b0;
        SSN          <= 1'b1;
        state_master <= MSTR_IDLE;
    end else if (SPISWAI) begin
        baud_en      <= baud_en;
        sck_en       <= sck_en;
        SPIF_set     <= SPIF_set;
        SPTEF_set    <= SPTEF_set;
        RX_data      <= RX_data;
        bit_cnt      <= bit_cnt;
        shifter      <= shifter;
        tx_pending   <= tx_pending;
        MOSI_out     <= MOSI_out;
        SSN          <= SSN;
        state_master <= state_master;
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
                bit_cnt      <= 3'd0;
                if (tx_pending || SPIDR_TX_valid) begin
                    baud_en         <= 1'b1;
                    sck_en          <= 1'b1;
                    SPTEF_set       <= 1'b1;
                    SSN             <= 1'b0;
                    shifter         <= SPIDR_TX_buffer;
                    tx_pending      <= 1'b0;    // clear pending flag
                    state_master    <= MSTR_Shift_Data;
                    if (CPHA == 1'b0) begin     // Give data before the first pulse
                        MOSI_out    <= LSBFE ? SPIDR_TX_buffer[0] : SPIDR_TX_buffer[7];
                    end
                end
            end

            MSTR_Shift_Data: begin
                if (shift_pulse) begin
                    // Detect if it is the last edge for CPHA = 0
                    if (CPHA == 1'b0 && bit_cnt == 3'd0) begin
                        baud_en      <= 1'b1;   // Still counting
                        sck_en       <= 1'b0;   // But stop sck output
                        state_master <= MSTR_TAIL_1;
                    end else begin
                        MOSI_out     <= LSBFE ? shifter[0] : shifter[7];
                    end
                end

                if (sample_pulse) begin
                    shifter  <= LSBFE ? {MISO_in, shifter[7:1]} : {shifter[6:0], MISO_in};

                    if (bit_cnt == 3'd7) begin
                        // Back to Back transfers, works when CPHA = 1
                        if (CPHA == 1'b1) begin
                            if (tx_pending || SPIDR_TX_valid) begin
                                bit_cnt      <= 3'd0;
                                SPIF_set     <= 1'b1;
                                SPTEF_set    <= 1'b1;
                                tx_pending   <= 1'b0;
                                shifter      <= SPIDR_TX_buffer;
                                state_master <= MSTR_Shift_Data;
                                // copy to rx_buffer
                                RX_data      <= LSBFE ? {MISO_in, shifter[7:1]} : {shifter[6:0], MISO_in};
                            end else begin
                                baud_en      <= 1'b1;   // Still counting
                                sck_en       <= 1'b0;   // But stop sck output
                                state_master <= MSTR_TAIL_1;
                            end
                        end else begin
                            // For CPHA = 0, it needs the last shift edge
                            bit_cnt <= 3'd0;
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
                    RX_data      <= shifter;
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
