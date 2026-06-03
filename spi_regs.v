module spi_regs (
    // APB
    input  wire        PCLK,
    input  wire        PRESETn,

    input  wire [3:0]  PADDR,
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [7:0]  PWDATA,
    output reg  [7:0]  PRDATA,
    output wire        PREADY,

    // Reg Output
    output reg  [7:0]  reg_SPICR1,
    output reg  [7:0]  reg_SPICR2,
    output reg  [7:0]  reg_SPIBR,

    // FSM Interface
    input  wire        fsm_SPIF_set,
    input  wire        fsm_SPTEF_set,
    input  wire        fsm_MODF_set,
    input  wire [7:0]  fsm_RX_data,
    output reg  [7:0]  reg_SPIDR_TX,
    output reg         reg_SPIDR_TX_valid
);

// Regs
reg  [7:0] reg_SPISR;
reg  [7:0] reg_SPIDR_RX;

// APB Signals
wire    APB_access   = PSEL && PENABLE;
wire    APB_write_en = APB_access && PWRITE;
wire    APB_read_en  = APB_access && !PWRITE;
assign  PREADY       = 1'b1;

// APB Write Data
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        reg_SPICR1          <= 8'h04;
        reg_SPICR2          <= 8'h00;
        reg_SPIBR           <= 8'h30;   // 8 div by default
        reg_SPIDR_TX        <= 8'h00;
        reg_SPIDR_TX_valid  <= 1'b0;
    end else begin
        reg_SPIDR_TX_valid <= 1'b0;     // 0 by default

        if (APB_write_en) begin
            case (PADDR)
                4'd0: reg_SPICR1    <= PWDATA;
                4'd1: reg_SPICR2    <= PWDATA;
                4'd2: reg_SPIBR     <= PWDATA;
                4'd5: begin     // SPISR can be written only when SPTEF is 1.
                    if (reg_SPISR[5]) begin
                        reg_SPIDR_TX        <= PWDATA;
                        reg_SPIDR_TX_valid  <= 1'b1;
                    end
                end
                default: ;
            endcase
        end
    end
end

// APB Read Data
// Receive RX data first.
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        reg_SPIDR_RX <= 8'h00;
    end else if (fsm_SPIF_set)begin
        if (!reg_SPISR[7])      // Copy data from shifter only when previous data was read (SPIF = 0)
            reg_SPIDR_RX <= fsm_RX_data;
    end
end
// Output Data
always @( *) begin
    PRDATA = 8'h0;
    if (APB_read_en) begin
        case (PADDR)
        4'd0: PRDATA = reg_SPICR1;
        4'd1: PRDATA = reg_SPICR2;
        4'd2: PRDATA = reg_SPIBR;
        4'd3: PRDATA = reg_SPISR;
        4'd5: PRDATA = reg_SPIDR_RX;
        default: PRDATA = 8'h0;    
        endcase
    end
end

// SPISR Clear Flag PRE
// To clear these flags, read SPISR first.
reg     SPIF_read;
reg     SPTEF_read;
reg     MODF_read;
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        SPIF_read   <= 1'b0;
        SPTEF_read  <= 1'b0;
        MODF_read   <= 1'b0;
    end else begin
        // Read SPISR
        if(APB_read_en && (PADDR == 4'd3)) begin
            if (reg_SPISR[7])
                SPIF_read   <= 1'b1;
            if (reg_SPISR[5])
                SPTEF_read  <= 1'b1;
            if (reg_SPISR[4])
                MODF_read   <= 1'b1;
        end else begin
            // Clear flags if having read/written SPIDR/SPICR1
            if (APB_read_en && (PADDR == 4'd5))
                SPIF_read   <= 1'b0;
            if (APB_write_en && (PADDR == 4'd5))
                SPTEF_read  <= 1'b0;
            if (APB_read_en && (PADDR == 4'd0))
                MODF_read   <= 1'b0;
        end
    end
end
// Set SPISR Next
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        reg_SPISR <= 8'h20;
    end else begin
        // SPIF
        if (fsm_SPIF_set) begin
            reg_SPISR[7] <= 1'b1;
        end else if (APB_read_en && (PADDR == 3'd5) && SPIF_read) begin
            reg_SPISR[7] <= 1'b0;
        end
        // SPTEF
        if (fsm_SPTEF_set) begin
            reg_SPISR[5] <= 1'b1;
        end else if (APB_write_en && (PADDR == 4'd5) && SPTEF_read) begin
            reg_SPISR[5] <= 1'b0;
        end
        // MODF
        if (fsm_MODF_set) begin
            reg_SPISR[4] <= 1'b1;
        end else if (APB_write_en && (PADDR == 3'd0) && MODF_read) begin
            reg_SPISR[4] <= 1'b0;
        end
    end
end

endmodule //spi_regs
