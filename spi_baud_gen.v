module spi_baud_gen (
    // APB
    input  wire        PCLK,
    input  wire        PRESETn,

    // Signals and Regs
    input  wire        MSTR,
    input  wire        CPOL,
    input  wire [7:0]  reg_SPIBR,

    // FSM Interface
    input  wire        fsm_active,
    // FSM clock pulse
    output reg         sck_rise_pulse,
    output reg         sck_fall_pulse,

    // Output
    output reg         sck_out
);

// SPPR and SPR
wire [2:0] SPPR = reg_SPIBR[6:4];
wire [2:0] SPR  = reg_SPIBR[2:0];

// Half - BaudRateDivisor
reg [11:0] Half_Divisor;
always @(*) begin
    // Half_Divisor = BaudRateDivisor / 2 = (SPPR + 1) * (2^SPR)
    case (SPR)
        3'd0: Half_Divisor = (SPPR + 1'b1) << 0;
        3'd1: Half_Divisor = (SPPR + 1'b1) << 1;
        3'd2: Half_Divisor = (SPPR + 1'b1) << 2;
        3'd3: Half_Divisor = (SPPR + 1'b1) << 3;
        3'd4: Half_Divisor = (SPPR + 1'b1) << 4;
        3'd5: Half_Divisor = (SPPR + 1'b1) << 5;
        3'd6: Half_Divisor = (SPPR + 1'b1) << 6;
        3'd7: Half_Divisor = (SPPR + 1'b1) << 7;
        default: Half_Divisor = 12'd1;
    endcase
end

// Clock Div
reg [11:0] sck_cnt;
reg        sck_state;
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        sck_cnt         <= 12'd0;
        sck_state       <= 1'b0;
        sck_rise_pulse  <= 1'b0;
        sck_fall_pulse  <= 1'b0;
    end else begin
        sck_rise_pulse  <= 1'b0;
        sck_fall_pulse  <= 1'b0;
        // Divisor works only in Master mode and when fsm is active
        if (MSTR && fsm_active) begin
            if (sck_cnt >= (Half_Divisor - 1'b1)) begin
                sck_cnt     <= 12'd0;
                sck_state   <= !sck_state;
                // Generate Pulse
                if (sck_state == 1'b0)
                    sck_rise_pulse <= 1'b1;
                else
                    sck_fall_pulse <= 1'b1;
            end else begin
                sck_cnt <= sck_cnt + 1'b1;
            end
        end else begin
            sck_cnt     <= 12'd0;
            sck_state   <= 1'b0;
        end
    end
end

// Generate Output sck
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        sck_out <= 1'b0;
    end else begin
        if (MSTR) begin
            if (fsm_active) begin
                if (sck_rise_pulse)
                    sck_out <= 1'b1;
                else if(sck_fall_pulse)
                    sck_out <= 1'b0;
            end else begin
                // IDLE
                sck_out <= CPOL;
            end
        end else begin
            // Slave, sck on top is chosen to be 1'bz.
            sck_out <= 1'b0;
        end
    end
end

endmodule //spi_baud_gen
