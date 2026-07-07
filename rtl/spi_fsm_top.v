module spi_fsm_top (
    // APB
    input  wire        PCLK,
    input  wire        PRESETn,

    // Regs
    input  wire [7:0]  reg_SPICR1,
    input  wire [7:0]  reg_SPICR2,
    input  wire [7:0]  reg_SPIBR,

    // Output
    output reg         master_en,
    output reg         slave_en
);

// Detect changes in some signals
reg [7:0] reg_SPICR1_r, reg_SPICR2_r, reg_SPIBR_r;
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        reg_SPICR1_r    <= 8'h04;
        reg_SPICR2_r    <= 8'h00;
        reg_SPIBR_r     <= 8'h30;
    end else begin
        reg_SPICR1_r    <= reg_SPICR1;
        reg_SPICR2_r    <= reg_SPICR2;
        reg_SPIBR_r     <= reg_SPIBR;
    end
end

wire cfg_changed = (reg_SPICR1[4:0] != reg_SPICR1_r[4:0]) || 
                   (reg_SPICR2[4] != reg_SPICR2_r[4]) || ((reg_SPICR2[3] != reg_SPICR2_r[3]) && (reg_SPICR2[0] == 1)) || (reg_SPICR2[0] != reg_SPICR2_r[0]) ||
                   (reg_SPIBR [6:4] != reg_SPIBR_r [6:4]) || (reg_SPIBR[2:0] != reg_SPIBR_r[2:0]);

// Top FSM
reg [1:0] state_top;
localparam INIT_IDLE    = 2'b00;
localparam MSTR_RUN     = 2'b01;
localparam SLV_RUN      = 2'b10;
assign SPE  = reg_SPICR1[6];
assign MSTR = reg_SPICR1[4];
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn || SPE == 1'b0) begin
        master_en <= 1'b0;
        slave_en  <= 1'b0;
        state_top <= INIT_IDLE;
    end else begin
        case (state_top)
            INIT_IDLE: begin
                master_en <= 1'b0;
                slave_en  <= 1'b0;
                if (SPE == 1'b1) begin
                    state_top <= MSTR ? MSTR_RUN : SLV_RUN;
                end
            end

            MSTR_RUN: begin
                master_en <= 1'b1;
                slave_en  <= 1'b0;
                if (cfg_changed) begin
                    state_top <= INIT_IDLE;
                end
            end

            SLV_RUN: begin
                master_en <= 1'b0;
                slave_en  <= 1'b1;
                // cannot return to INIT_IDLE except SPE and PRESETn and MSTR
                if (reg_SPICR2[4] != reg_SPICR2_r[4]) begin
                    state_top   <= INIT_IDLE;
                end
            end

            default: state_top <= INIT_IDLE;
        endcase
    end
end

endmodule //spi_fsm_top
