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
    input  wire        WAIT,
    input  wire        CPOL,
    input  wire        CPHA,
    input  wire        LSBFE,
    input  wire        SPIDR_TX_valid,
    input  wire [7:0]  SPIDR_TX_buffer,

    // Ctrl baud_gen
    output reg         fsm_active,

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
localparam MSTR_Half_Delay  = 2'b01;
localparam MSTR_Shift_Data  = 2'b10;
localparam MSTR_TAIL        = 2'b11;
reg [2:0] bit_cnt;
reg [7:0] shifter;
reg       miso_latch;
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn || !master_en) begin
        fsm_active   <= 1'b0;
        SPIF_set     <= 1'b0;
        SPTEF_set    <= 1'b1;
        RX_data      <= 8'h00;
        bit_cnt      <= 3'd0;
        shifter      <= 8'h00;
        MOSI_out     <= 1'b0;
        SSN          <= 1'b1;
        state_master <= MSTR_IDLE;
    end else if (WAIT) begin
        fsm_active   <= fsm_active;
        SPIF_set     <= SPIF_set;
        SPTEF_set    <= SPTEF_set;
        RX_data      <= RX_data;
        bit_cnt      <= bit_cnt;
        shifter      <= shifter;
        MOSI_out     <= MOSI_out;
        SSN          <= SSN;
        state_master <= state_master;
    end else begin
        case (state_master)
            MSTR_IDLE: begin
                SPIF_set     <= 1'b0;
                bit_cnt      <= 3'd0;
                if (SPIDR_TX_valid) begin
                    fsm_active      <= 1'b1;
                    SPTEF_set       <= 1'b0;
                    SSN             <= 1'b0;
                    shifter         <= SPIDR_TX_buffer;
                    state_master    <= MSTR_Half_Delay;
                    if (CPHA == 1'b0) begin     // Give data before the first pulse
                        MOSI_out <= LSBFE ? SPIDR_TX_buffer[0] : SPIDR_TX_buffer[7];
                    end
                end
            end

            MSTR_Half_Delay: begin
                if (sck_rise_pulse || sck_fall_pulse) begin
                    state_master <= MSTR_Shift_Data;
                    if (CPHA == 1'b1) begin
                        MOSI_out <= LSBFE ? shifter[0] : shifter[7];
                    end
                end
            end

            MSTR_Shift_Data: begin
                if (sample_pulse) begin
                    miso_latch <= MISO_in;
                end

                if (shift_pulse) begin
                    if (bit_cnt == 3'd7) begin
                        state_master <= MSTR_TAIL;
                    end else begin
                        if (LSBFE) begin
                            MOSI_out <= shifter[1];
                            shifter <= {miso_latch, shifter[7:1]};
                        end else begin
                            MOSI_out <= shifter[6];
                            shifter <= {shifter[6:0], miso_latch};
                        end
                    end
                    bit_cnt <= bit_cnt + 1'b1;
                end
            end

            MSTR_TAIL: begin
                if (sck_rise_pulse || sck_fall_pulse) begin
                    fsm_active   <= 1'b0;
                    SPIF_set     <= 1'b1;
                    SPTEF_set    <= 1'b1;
                    RX_data      <= shifter;
                    MOSI_out     <= 1'b0;
                    SSN          <= 1'b1;
                    state_master <= MSTR_IDLE;
                end
            end

            default: state_master <= MSTR_IDLE;
        endcase
    end     
end

endmodule //spi_master
