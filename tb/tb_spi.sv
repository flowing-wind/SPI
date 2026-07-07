//-----------------------------------------------------------------------------
// tb_spi.sv - Self-checking functional testbench for the SPI IP core
//
// Two spi_top instances are cross-connected pad-to-pad:
//   DUT_M : configured as master
//   DUT_S : configured as slave
// A simple APB3 BFM (2-cycle accesses, PREADY tied high) drives both.
//
// Covered:
//   T1  Register reset values
//   T2  Register write/read access
//   T3  Full-duplex transfers: 8/16/32-bit x CPOL/CPHA (all 4 modes)
//   T4  LSB-first transfers
//   T5  SPIDR write without SPTEF-read handshake is ignored
//   T6  SPIF flag clearing protocol (read SPISR then SPIDR)
//   T7  Back-to-back transfers (CPHA=1)
//   T8  Bidirectional mode (master MOMI -> slave SISO)
//   T9  Mode fault (MODF): flag, MSTR auto-clear, interrupt, clear sequence
//
// Run (Icarus Verilog, from the tb/ directory):
//   iverilog -g2012 -o spi_tb.vvp ../rtl/*.v tb_spi.sv && vvp spi_tb.vvp
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_spi;

    // Register byte offsets (word aligned)
    localparam [4:0] A_SPICR1 = 5'h00;
    localparam [4:0] A_SPICR2 = 5'h04;
    localparam [4:0] A_SPIBR  = 5'h08;
    localparam [4:0] A_SPISR  = 5'h0C;
    localparam [4:0] A_SPIFW  = 5'h10;
    localparam [4:0] A_SPIDR  = 5'h14;

    // SPISR bits
    localparam SPIF_BIT  = 7;
    localparam SPTEF_BIT = 5;
    localparam MODF_BIT  = 4;

    // Clock / reset
    reg PCLK    = 1'b0;
    reg PRESETn = 1'b0;
    always #5 PCLK = ~PCLK;     // 100 MHz

    // APB - master DUT
    reg  [4:0]  m_paddr;
    reg         m_psel, m_penable, m_pwrite;
    reg  [31:0] m_pwdata;
    wire [31:0] m_prdata;
    wire        m_pready;
    wire        m_irq;

    // APB - slave DUT
    reg  [4:0]  s_paddr;
    reg         s_psel, s_penable, s_pwrite;
    reg  [31:0] s_pwdata;
    wire [31:0] s_prdata;
    wire        s_pready;
    wire        s_irq;

    // Pads
    wire m_sck_o,  m_sck_oe,  m_mosi_o, m_mosi_oe;
    wire m_miso_o, m_miso_oe, m_ssn_o,  m_ssn_oe;
    wire s_sck_o,  s_sck_oe,  s_mosi_o, s_mosi_oe;
    wire s_miso_o, s_miso_oe, s_ssn_o,  s_ssn_oe;

    reg  tb_m_ssn_in = 1'b1;    // testbench-driven SS input of the master (mode fault)

    // Shared board-level wires
    wire bus_sck  = m_sck_oe  ? m_sck_o  : 1'b0;
    wire bus_mosi = m_mosi_oe ? m_mosi_o : 1'b0;
    wire bus_miso = s_miso_oe ? s_miso_o : 1'b0;
    wire bus_ssn  = m_ssn_oe  ? m_ssn_o  : 1'b1;

    // DUTs
    spi_top DUT_M (
        .PCLK(PCLK), .PRESETn(PRESETn),
        .PADDR(m_paddr), .PSEL(m_psel), .PENABLE(m_penable),
        .PWRITE(m_pwrite), .PWDATA(m_pwdata), .PRDATA(m_prdata), .PREADY(m_pready),
        .spi_irq(m_irq),
        .sck_pad_i (1'b0),        .sck_pad_o (m_sck_o),  .sck_pad_oe (m_sck_oe),
        .mosi_pad_i(bus_mosi),    .mosi_pad_o(m_mosi_o), .mosi_pad_oe(m_mosi_oe),
        .miso_pad_i(bus_miso),    .miso_pad_o(m_miso_o), .miso_pad_oe(m_miso_oe),
        .ssn_pad_i (tb_m_ssn_in), .ssn_pad_o (m_ssn_o),  .ssn_pad_oe (m_ssn_oe)
    );

    spi_top DUT_S (
        .PCLK(PCLK), .PRESETn(PRESETn),
        .PADDR(s_paddr), .PSEL(s_psel), .PENABLE(s_penable),
        .PWRITE(s_pwrite), .PWDATA(s_pwdata), .PRDATA(s_prdata), .PREADY(s_pready),
        .spi_irq(s_irq),
        .sck_pad_i (bus_sck),  .sck_pad_o (s_sck_o),  .sck_pad_oe (s_sck_oe),
        .mosi_pad_i(bus_mosi), .mosi_pad_o(s_mosi_o), .mosi_pad_oe(s_mosi_oe),
        .miso_pad_i(bus_mosi), .miso_pad_o(s_miso_o), .miso_pad_oe(s_miso_oe),
        .ssn_pad_i (bus_ssn),  .ssn_pad_o (s_ssn_o),  .ssn_pad_oe (s_ssn_oe)
    );

    //-------------------------------------------------------------------------
    // APB BFM
    //-------------------------------------------------------------------------
    localparam M = 0, S = 1;

    task apb_wr(input integer sel, input [4:0] addr, input [31:0] data);
    begin
        @(posedge PCLK);
        if (sel == M) begin
            m_paddr <= addr; m_pwdata <= data; m_pwrite <= 1'b1;
            m_psel  <= 1'b1; m_penable <= 1'b0;
        end else begin
            s_paddr <= addr; s_pwdata <= data; s_pwrite <= 1'b1;
            s_psel  <= 1'b1; s_penable <= 1'b0;
        end
        @(posedge PCLK);
        if (sel == M) m_penable <= 1'b1; else s_penable <= 1'b1;
        @(posedge PCLK);
        if (sel == M) begin m_psel <= 1'b0; m_penable <= 1'b0; m_pwrite <= 1'b0; end
        else          begin s_psel <= 1'b0; s_penable <= 1'b0; s_pwrite <= 1'b0; end
    end
    endtask

    task apb_rd(input integer sel, input [4:0] addr, output [31:0] data);
    begin
        @(posedge PCLK);
        if (sel == M) begin
            m_paddr <= addr; m_pwrite <= 1'b0;
            m_psel  <= 1'b1; m_penable <= 1'b0;
        end else begin
            s_paddr <= addr; s_pwrite <= 1'b0;
            s_psel  <= 1'b1; s_penable <= 1'b0;
        end
        @(posedge PCLK);
        if (sel == M) m_penable <= 1'b1; else s_penable <= 1'b1;
        @(posedge PCLK);
        data = (sel == M) ? m_prdata : s_prdata;
        if (sel == M) begin m_psel <= 1'b0; m_penable <= 1'b0; end
        else          begin s_psel <= 1'b0; s_penable <= 1'b0; end
    end
    endtask

    //-------------------------------------------------------------------------
    // Check helpers
    //-------------------------------------------------------------------------
    integer err_cnt  = 0;
    integer test_cnt = 0;

    task check(input [31:0] actual, input [31:0] expected, input [255:0] msg);
    begin
        test_cnt = test_cnt + 1;
        if (actual !== expected) begin
            err_cnt = err_cnt + 1;
            $display("  [FAIL] %0s : actual=0x%08h expected=0x%08h (t=%0t)",
                     msg, actual, expected, $time);
        end
    end
    endtask

    task check_bit(input actual, input expected, input [255:0] msg);
    begin
        test_cnt = test_cnt + 1;
        if (actual !== expected) begin
            err_cnt = err_cnt + 1;
            $display("  [FAIL] %0s : actual=%b expected=%b (t=%0t)",
                     msg, actual, expected, $time);
        end
    end
    endtask

    //-------------------------------------------------------------------------
    // SPI helper tasks
    //-------------------------------------------------------------------------
    reg [31:0] rdat;    // scratch

    // Poll SPISR until a flag is set (also performs the SPISR read that arms
    // the flag-clearing sequence)
    task poll_flag(input integer sel, input integer flag_bit);
        integer guard;
        reg [31:0] v;
    begin
        guard = 0;
        v = 32'h0;
        while (!v[flag_bit] && guard < 3000) begin
            apb_rd(sel, A_SPISR, v);
            guard = guard + 1;
        end
        if (guard >= 3000) begin
            err_cnt = err_cnt + 1;
            $display("  [FAIL] timeout polling SPISR bit %0d on %0s (t=%0t)",
                     flag_bit, (sel == M) ? "MASTER" : "SLAVE", $time);
        end
    end
    endtask

    // Read SPISR until SPTEF=1, then write SPIDR (queues TX data)
    task spi_tx(input integer sel, input [31:0] data);
    begin
        poll_flag(sel, SPTEF_BIT);
        apb_wr(sel, A_SPIDR, data);
    end
    endtask

    // Wait for SPIF then read the received frame
    task spi_rx(input integer sel, output [31:0] data);
    begin
        poll_flag(sel, SPIF_BIT);
        apb_rd(sel, A_SPIDR, data);
    end
    endtask

    // Disable both DUTs (resets status flags / FSMs)
    task spi_disable_both;
    begin
        apb_wr(M, A_SPICR1, 32'h04);
        apb_wr(S, A_SPICR1, 32'h04);
        repeat (4) @(posedge PCLK);
    end
    endtask

    // Configure master + slave pair.
    //   cpol/cpha/lsbfe: SPI mode;  fw: 0=8b, 1=16b, 2=32b
    task spi_config_pair(input cpol, input cpha, input lsbfe, input [1:0] fw);
        reg [7:0] cr1_m, cr1_s;
    begin
        // {SPIE,SPE,SPTIE,0,MSTR,CPOL,CPHA,SSOE,LSBFE}
        cr1_m = {1'b0, 1'b1, 1'b0, 1'b1, cpol, cpha, 1'b1, lsbfe};  // master, SSOE=1
        cr1_s = {1'b0, 1'b1, 1'b0, 1'b0, cpol, cpha, 1'b0, lsbfe};  // slave
        apb_wr(M, A_SPIBR,  32'h31);        // divisor 16 -> slow enough for slave CDC
        apb_wr(M, A_SPIFW,  {30'h0, fw});
        apb_wr(M, A_SPICR2, 32'h10);        // MODFEN=1 (with SSOE=1 -> SS output)
        apb_wr(M, A_SPICR1, {24'h0, cr1_m});
        apb_wr(S, A_SPIFW,  {30'h0, fw});
        apb_wr(S, A_SPICR2, 32'h00);
        apb_wr(S, A_SPICR1, {24'h0, cr1_s});
        repeat (6) @(posedge PCLK);         // let the mode FSMs settle
    end
    endtask

    function [31:0] fw_mask(input [1:0] fw);
        case (fw)
            2'd1:    fw_mask = 32'h0000_FFFF;
            2'd2:    fw_mask = 32'hFFFF_FFFF;
            default: fw_mask = 32'h0000_00FF;
        endcase
    endfunction

    // One full-duplex transfer + check both directions
    task xfer_check(input [31:0] m_data, input [31:0] s_data, input [1:0] fw,
                    input [255:0] tag);
        reg [31:0] m_rx, s_rx;
    begin
        spi_tx(S, s_data);                  // slave queues its reply first
        spi_tx(M, m_data);                  // master starts the transfer
        spi_rx(M, m_rx);
        spi_rx(S, s_rx);
        check(m_rx, s_data & fw_mask(fw), {tag, " master RX"});
        check(s_rx, m_data & fw_mask(fw), {tag, " slave RX"});
    end
    endtask

    //-------------------------------------------------------------------------
    // Test sequence
    //-------------------------------------------------------------------------
    integer cpol_i, cpha_i, fw_i;
    reg [31:0] v0, v1;

    initial begin
        $dumpfile("tb_spi.vcd");
        $dumpvars(0, tb_spi);

        m_paddr = 0; m_psel = 0; m_penable = 0; m_pwrite = 0; m_pwdata = 0;
        s_paddr = 0; s_psel = 0; s_penable = 0; s_pwrite = 0; s_pwdata = 0;

        repeat (5) @(posedge PCLK);
        PRESETn = 1'b1;
        repeat (5) @(posedge PCLK);

        //---------------------------------------------------------------
        $display("T1: register reset values");
        //---------------------------------------------------------------
        apb_rd(M, A_SPICR1, rdat); check(rdat, 32'h04, "SPICR1 reset");
        apb_rd(M, A_SPICR2, rdat); check(rdat, 32'h00, "SPICR2 reset");
        apb_rd(M, A_SPIBR,  rdat); check(rdat, 32'h30, "SPIBR reset");
        apb_rd(M, A_SPISR,  rdat); check(rdat, 32'h20, "SPISR reset (SPTEF=1)");
        apb_rd(M, A_SPIFW,  rdat); check(rdat, 32'h00, "SPIFW reset (8-bit)");
        apb_rd(M, A_SPIDR,  rdat); check(rdat, 32'h00, "SPIDR reset");

        //---------------------------------------------------------------
        $display("T2: register write/read access");
        //---------------------------------------------------------------
        apb_wr(M, A_SPIBR, 32'h55);
        apb_rd(M, A_SPIBR, rdat); check(rdat, 32'h55, "SPIBR RW");
        apb_wr(M, A_SPIBR, 32'h30);
        apb_wr(M, A_SPIFW, 32'hFFFF_FFFE);              // only [1:0] writable
        apb_rd(M, A_SPIFW, rdat); check(rdat, 32'h02, "SPIFW RW + reserved bits");
        apb_wr(M, A_SPIFW, 32'h00);
        apb_wr(M, A_SPISR, 32'hFF);                     // read-only
        apb_rd(M, A_SPISR, rdat); check(rdat, 32'h20, "SPISR write ignored");

        //---------------------------------------------------------------
        $display("T3: 8/16/32-bit transfers, all CPOL/CPHA modes (MSB first)");
        //---------------------------------------------------------------
        for (fw_i = 0; fw_i <= 2; fw_i = fw_i + 1) begin
            for (cpol_i = 0; cpol_i <= 1; cpol_i = cpol_i + 1) begin
                for (cpha_i = 0; cpha_i <= 1; cpha_i = cpha_i + 1) begin
                    $display("  fw=%0d-bit cpol=%0d cpha=%0d", 8 << fw_i, cpol_i, cpha_i);
                    spi_disable_both;
                    spi_config_pair(cpol_i[0], cpha_i[0], 1'b0, fw_i[1:0]);
                    xfer_check(32'hA5C3_96E1, 32'h5A3C_691E, fw_i[1:0], "T3a");
                    xfer_check(32'h1234_5678, 32'h9ABC_DEF0, fw_i[1:0], "T3b");
                end
            end
        end

        //---------------------------------------------------------------
        $display("T4: LSB-first transfers");
        //---------------------------------------------------------------
        spi_disable_both;
        spi_config_pair(1'b0, 1'b0, 1'b1, 2'd0);        // 8-bit LSB first
        xfer_check(32'h0000_00B7, 32'h0000_002D, 2'd0, "T4-8b");
        spi_disable_both;
        spi_config_pair(1'b1, 1'b1, 1'b1, 2'd2);        // 32-bit LSB first
        xfer_check(32'hDEAD_BEEF, 32'hCAFE_F00D, 2'd2, "T4-32b");

        //---------------------------------------------------------------
        $display("T5: SPIDR write without SPTEF handshake is ignored");
        //---------------------------------------------------------------
        spi_disable_both;
        spi_config_pair(1'b0, 1'b0, 1'b0, 2'd0);
        // Read SPIDR (clears any SPTEF_read arming), then write without SPISR read
        apb_rd(M, A_SPIDR, rdat);
        apb_wr(M, A_SPIDR, 32'hFF);
        repeat (40) @(posedge PCLK);
        check_bit(m_ssn_o, 1'b1, "T5 no transfer started (SSN idle)");
        apb_rd(M, A_SPISR, rdat);
        check_bit(rdat[SPIF_BIT], 1'b0, "T5 SPIF still clear");

        //---------------------------------------------------------------
        $display("T6: SPIF clearing protocol");
        //---------------------------------------------------------------
        spi_disable_both;
        spi_config_pair(1'b0, 1'b0, 1'b0, 2'd0);
        spi_tx(S, 32'h77);
        spi_tx(M, 32'h88);
        poll_flag(M, SPIF_BIT);                         // read SPISR with SPIF=1
        apb_rd(M, A_SPISR, v0);
        check_bit(v0[SPIF_BIT], 1'b1, "T6 SPIF set before SPIDR read");
        apb_rd(M, A_SPIDR, v1);
        check(v1, 32'h77, "T6 master RX data");
        apb_rd(M, A_SPISR, v0);
        check_bit(v0[SPIF_BIT], 1'b0, "T6 SPIF cleared after SPISR+SPIDR reads");

        //---------------------------------------------------------------
        $display("T7: back-to-back transfers (CPHA=1)");
        //---------------------------------------------------------------
        spi_disable_both;
        spi_config_pair(1'b0, 1'b1, 1'b0, 2'd0);
        spi_tx(S, 32'h11);
        spi_tx(M, 32'hA1);                              // first frame starts
        spi_tx(M, 32'hA2);                              // queued during frame 1
        spi_rx(M, v0); check(v0, 32'h11, "T7 master RX frame1");
        spi_rx(S, v1); check(v1, 32'hA1, "T7 slave RX frame1");
        spi_rx(S, v1); check(v1, 32'hA2, "T7 slave RX frame2");

        //---------------------------------------------------------------
        $display("T8: bidirectional mode, master MOMI -> slave SISO");
        //---------------------------------------------------------------
        spi_disable_both;
        // master: SPC0=1, BIDIROE=1 (drives MOMI); slave: SPC0=1, BIDIROE=0 (receives on SISO)
        apb_wr(M, A_SPIBR,  32'h31);
        apb_wr(M, A_SPIFW,  32'h00);
        apb_wr(M, A_SPICR2, 32'h19);        // MODFEN=1, BIDIROE=1, SPC0=1
        apb_wr(M, A_SPICR1, 32'h52);        // SPE, MSTR, SSOE
        apb_wr(S, A_SPIFW,  32'h00);
        apb_wr(S, A_SPICR2, 32'h01);        // SPC0=1, BIDIROE=0
        apb_wr(S, A_SPICR1, 32'h40);        // SPE, slave
        repeat (6) @(posedge PCLK);
        spi_tx(M, 32'h3C);
        spi_rx(S, v0); check(v0, 32'h3C, "T8 slave RX via SISO");
        spi_rx(M, v1); check(v1, 32'h3C, "T8 master loopback via MOMI");

        //---------------------------------------------------------------
        $display("T9: mode fault");
        //---------------------------------------------------------------
        spi_disable_both;
        apb_wr(M, A_SPIBR,  32'h31);
        apb_wr(M, A_SPIFW,  32'h00);
        apb_wr(M, A_SPICR2, 32'h10);        // MODFEN=1, SSOE=0 -> SS input w/ MODF
        apb_wr(M, A_SPICR1, 32'hD0);        // SPIE, SPE, MSTR
        repeat (6) @(posedge PCLK);
        tb_m_ssn_in = 1'b0;                 // another master drives SS low
        repeat (8) @(posedge PCLK);
        apb_rd(M, A_SPISR, v0);
        check_bit(v0[MODF_BIT], 1'b1, "T9 MODF set");
        apb_rd(M, A_SPICR1, v1);
        check_bit(v1[4], 1'b0, "T9 MSTR auto-cleared");
        check_bit(m_irq, 1'b1, "T9 interrupt asserted");
        check_bit(m_sck_oe | m_mosi_oe | m_miso_oe, 1'b0, "T9 outputs disabled");
        tb_m_ssn_in = 1'b1;
        repeat (4) @(posedge PCLK);
        // clear: read SPISR (MODF=1) then write SPICR1
        apb_rd(M, A_SPISR, v0);
        apb_wr(M, A_SPICR1, 32'hD0);
        repeat (2) @(posedge PCLK);
        apb_rd(M, A_SPISR, v0);
        check_bit(v0[MODF_BIT], 1'b0, "T9 MODF cleared");
        check_bit(m_irq, 1'b0, "T9 interrupt deasserted");

        //---------------------------------------------------------------
        $display("T9b: mode fault in bidirectional master mode clears BIDIROE");
        //---------------------------------------------------------------
        spi_disable_both;
        apb_wr(M, A_SPICR2, 32'h19);        // MODFEN=1, BIDIROE=1, SPC0=1
        apb_wr(M, A_SPICR1, 32'h50);        // SPE, MSTR (SSOE=0 -> SS input w/ MODF)
        repeat (6) @(posedge PCLK);
        tb_m_ssn_in = 1'b0;
        repeat (8) @(posedge PCLK);
        apb_rd(M, A_SPISR, v0);
        check_bit(v0[MODF_BIT], 1'b1, "T9b MODF set");
        apb_rd(M, A_SPICR2, v1);
        check_bit(v1[3], 1'b0, "T9b BIDIROE auto-cleared");
        check_bit(v1[0], 1'b1, "T9b SPC0 unchanged");
        tb_m_ssn_in = 1'b1;
        repeat (4) @(posedge PCLK);
        apb_rd(M, A_SPISR, v0);             // arm MODF clear
        apb_wr(M, A_SPICR1, 32'h50);        // clear MODF

        //---------------------------------------------------------------
        // Summary
        //---------------------------------------------------------------
        repeat (10) @(posedge PCLK);
        $display("--------------------------------------------------");
        if (err_cnt == 0)
            $display("TEST PASSED : %0d checks, 0 errors", test_cnt);
        else
            $display("TEST FAILED : %0d checks, %0d errors", test_cnt, err_cnt);
        $display("--------------------------------------------------");
        $finish;
    end

    // Global watchdog
    initial begin
        #10_000_000;
        $display("[FATAL] global watchdog timeout");
        $finish;
    end

endmodule
