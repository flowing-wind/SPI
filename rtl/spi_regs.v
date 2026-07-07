module spi_regs (
    // APB
    input  wire        PCLK,
    input  wire        PRESETn,

    input  wire [4:0]  PADDR,
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [31:0] PWDATA,
    output reg  [31:0] PRDATA,
    output wire        PREADY,

    // Reg Output
    output reg  [7:0]  reg_SPICR1,
    output reg  [7:0]  reg_SPICR2,
    output reg  [7:0]  reg_SPIBR,
    output reg  [1:0]  reg_SPIFW,

    // MSTR/SLV Interface
    input  wire        SPIF_set,
    input  wire        SPTEF_set,
    input  wire        MODF_set,
    input  wire [31:0] RX_data,
    output reg  [31:0] reg_SPIDR_TX,
    output reg         SPIDR_TX_valid,

    // MODF Interface
    output wire        MODF_flag,

    // Interrupt Request
    output wire        spi_irq
);

// Word-aligned register offsets (byte address = index << 2)
localparam ADDR_SPICR1 = 3'd0;  // 0x00
localparam ADDR_SPICR2 = 3'd1;  // 0x04
localparam ADDR_SPIBR  = 3'd2;  // 0x08
localparam ADDR_SPISR  = 3'd3;  // 0x0C
localparam ADDR_SPIFW  = 3'd4;  // 0x10 (reserved $4 in the S12 map, used as frame width)
localparam ADDR_SPIDR  = 3'd5;  // 0x14

wire [2:0] word_addr = PADDR[4:2];

// Regs
reg  [7:0]  reg_SPISR;
reg  [31:0] reg_SPIDR_RX;
// Reg Configurations
wire SPIE    = reg_SPICR1[7];
wire SPE     = reg_SPICR1[6];
wire SPTIE   = reg_SPICR1[5];

wire SPIF    = reg_SPISR[7];
wire SPTEF   = reg_SPISR[5];
wire MODF    = reg_SPISR[4];

assign MODF_flag = MODF;
assign spi_irq   = SPE & ((SPIE & (SPIF | MODF)) | (SPTIE & SPTEF));

// To clear flags, read SPISR first.
reg     SPIF_read;
reg     SPTEF_read;
reg     MODF_read;

// APB Signals
wire    APB_access   = PSEL && PENABLE;
wire    APB_write_en = APB_access && PWRITE;
wire    APB_read_en  = APB_access && !PWRITE;
assign  PREADY       = 1'b1;

// APB Write Data
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        reg_SPICR1      <= 8'h04;
        reg_SPICR2      <= 8'h00;
        reg_SPIBR       <= 8'h30;   // 8 div by default
        reg_SPIFW       <= 2'b00;   // 8-bit frames by default
        reg_SPIDR_TX    <= 32'h0;
        SPIDR_TX_valid  <= 1'b0;
    end else begin
        SPIDR_TX_valid      <= 1'b0;     // 0 by default

        if (APB_write_en) begin
            case (word_addr)
                ADDR_SPICR1: reg_SPICR1 <= PWDATA[7:0];
                ADDR_SPICR2: reg_SPICR2 <= PWDATA[7:0] & 8'h1B;  // reserved bits stay 0
                ADDR_SPIBR : reg_SPIBR  <= PWDATA[7:0] & 8'h77;  // reserved bits stay 0
                ADDR_SPIFW : reg_SPIFW  <= PWDATA[1:0];
                ADDR_SPIDR : begin  // SPIDR can be written only when SPTEF is 1.
                    if (SPTEF & SPTEF_read) begin
                        reg_SPIDR_TX    <= PWDATA;
                        SPIDR_TX_valid  <= 1'b1;
                    end
                end
                default: ;
            endcase
        end

        if (MODF_set) begin
            reg_SPICR1[4]   <= 1'b0;  // change to slave
            if (reg_SPICR2[0]) begin  // bidirectional mode: clear MOMI output enable
                reg_SPICR2[3]   <= 1'b0;
            end
        end
    end
end

// APB Read Data
// Receive RX data first.
reg rx_pending;
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        reg_SPIDR_RX <= 32'h0;
        rx_pending   <= 1'b0;
    end else if (!SPE) begin
        reg_SPIDR_RX <= 32'h0;
        rx_pending   <= 1'b0;
    end else begin
        if (SPIF_set)begin
            if (!SPIF) begin    // Copy data from shifter only when previous data was read (SPIF = 0)
                reg_SPIDR_RX <= RX_data;
            end else begin      // Otherwise the second received data should be pending
                rx_pending   <= 1'b1;
            end
        end
        // If CPU is reading RX, push the second rx_data into SPIDR_RX
        else if(APB_read_en && (word_addr == ADDR_SPIDR) && SPIF_read) begin
            if (rx_pending) begin
                reg_SPIDR_RX <= RX_data;
                rx_pending   <= 1'b0;
            end
        end
    end
end
// Output Data
always @( *) begin
    PRDATA = 32'h0;
    if (APB_read_en) begin
        case (word_addr)
        ADDR_SPICR1: PRDATA = {24'h0, reg_SPICR1};
        ADDR_SPICR2: PRDATA = {24'h0, reg_SPICR2};
        ADDR_SPIBR : PRDATA = {24'h0, reg_SPIBR};
        ADDR_SPISR : PRDATA = {24'h0, reg_SPISR};
        ADDR_SPIFW : PRDATA = {30'h0, reg_SPIFW};
        ADDR_SPIDR : PRDATA = reg_SPIDR_RX;
        default: PRDATA = 32'h0;
        endcase
    end
end

// SPISR Clear Flag PRE
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        SPIF_read   <= 1'b0;
        SPTEF_read  <= 1'b0;
        MODF_read   <= 1'b0;
    end else if (!SPE) begin
        SPIF_read   <= 1'b0;
        SPTEF_read  <= 1'b0;
        MODF_read   <= 1'b0;
    end else begin
        // Read SPISR
        if(APB_read_en && (word_addr == ADDR_SPISR)) begin
            if (SPIF)
                SPIF_read   <= 1'b1;
            if (SPTEF)
                SPTEF_read  <= 1'b1;
            if (MODF)
                MODF_read   <= 1'b1;
        end else begin
            // Clear flags if having read/written SPIDR/SPICR1
            if (APB_read_en && (word_addr == ADDR_SPIDR))
                SPIF_read   <= 1'b0;
            if (APB_write_en && (word_addr == ADDR_SPIDR))
                SPTEF_read  <= 1'b0;
            if (APB_write_en && (word_addr == ADDR_SPICR1))
                MODF_read   <= 1'b0;
        end
    end
end
// Set SPISR Next
always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        reg_SPISR <= 8'h20;
    end else if (!SPE) begin
        reg_SPISR <= 8'h20;
    end else begin
        // SPIF
        if (SPIF_set) begin
            reg_SPISR[7]    <= 1'b1;
        end else if (APB_read_en && (word_addr == ADDR_SPIDR) && SPIF_read) begin
            if (rx_pending) begin   // The second data is pending
                reg_SPISR[7]    <= 1'b1;
            end else begin
                reg_SPISR[7]    <= 1'b0;
            end
        end
        // SPTEF
        // APB write has higher priority
        if (APB_write_en && (word_addr == ADDR_SPIDR) && SPTEF_read) begin
            reg_SPISR[5]    <= 1'b0;
        end else if (SPTEF_set) begin
            reg_SPISR[5]    <= 1'b1;
        end
        // MODF
        if (MODF_set) begin
            reg_SPISR[4]    <= 1'b1;
        end else if (APB_write_en && (word_addr == ADDR_SPICR1) && MODF_read) begin
            reg_SPISR[4]    <= 1'b0;
        end
    end
end

endmodule //spi_regs
