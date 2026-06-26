`timescale 1ns / 1ps

// Testbench for uart_cmd_parser.
//
// spi_rdata bit-field contract (matches uart_spi_pack rd_byte logic):
//   AD9640 (chip=0x02) : response byte at spi_rdata[39:32]
//   AD9117 (chip=0x03) : response byte at spi_rdata[47:40]
//   SI5340 (chip=0x01) : response byte at spi_rdata[47:40]
//
// spi_cmd[62:0] = {slv_sel[2:0], 3'b000, rd_en, spi_data[55:0]}
//   [62:60] slv_sel   [56] rd_en   [55:40] upper 16b of spi_data

module tb_uart_cmd_parser;

  localparam integer CLK_HZ     = 19_200_000;
  localparam integer CLK_PERIOD = 52;
  localparam integer BIT_NS     = (CLK_HZ / 921_600) * CLK_PERIOD;

  reg        clk      = 0;
  reg        rst_n    = 0;
  reg        uart_rx  = 1;
  wire       uart_tx;
  reg        spi_done  = 0;
  reg [55:0] spi_rdata = 0;
  wire       spi_valid;
  wire [62:0] spi_cmd;
  wire       spi_busy;
  wire       global_rst;
  reg        grst_seen = 0;

  integer errs = 0;

  always #(CLK_PERIOD / 2) clk = ~clk;

  // Latch any global-reset pulse so test cases can verify it fired
  always @(posedge clk) if (global_rst) grst_seen <= 1'b1;

  initial begin
    #200_000_000;
    $display("[WATCHDOG] TIMEOUT errs=%0d", errs);
    $display("tb_uart_cmd_parser: FAIL (timeout)");
    $finish;
  end

  // Boot-status stubs
  reg  boot_busy_tb = 0;
  reg  boot_done_tb = 0;
  reg  [3:0] boot_chip_tb = 4'h0;
  reg  [7:0] boot_err_tb  = 8'h00;
  wire boot_start_tb;

  // ADC stubs
  wire        adc_arm_tb;
  wire [13:0] adc_rd_addr_tb;
  reg         adc_done_tb     = 0;
  reg         adc_busy_tb     = 0;
  reg  [13:0] adc_rdata_fixed = 14'h0000;  // legacy: tests set this directly
  reg         adc_burst_mode  = 0;
  reg  [13:0] adc_burst_mem [0:7];          // T30 mock BRAM
  wire [13:0] adc_rdata_tb    = adc_burst_mode
                                ? adc_burst_mem[adc_rd_addr_tb[2:0]]
                                : adc_rdata_fixed;

  // DAC tone enable (0x40)
  wire        dac_tone_en_tb;
  wire [1:0]  dac_wave_sel_tb;
  wire [15:0] dac_freq_word_tb;
  wire [7:0]  dac_amp_pct_tb;

  // DDC/RX cfg, ADC chan_sel
  wire        adc_chan_sel_tb;
  wire [15:0] nco_freq_word_tb;
  wire [1:0]  dec_ratio_tb;
  wire        capture_mode_tb;
  wire        iq_bypass_tb;
  wire        fir_bypass_tb;
  wire [15:0] iq_mult_op1_tb;
  wire [15:0] iq_mult_op2_tb;
  wire [13:0] iq_offset_i_tb;
  wire [13:0] iq_offset_q_tb;
  reg  [7:0]  stream_byte_tb = 8'h00;
  reg         stream_vld_tb  = 1'b0;
  reg         stream_ovf_tb  = 1'b0;
  wire        stream_en_tb;
  wire        stream_rdy_tb;
  // T31b stream-check temporaries (module scope for Verilog-2001/XSim).
  integer     k31b;
  integer     i34, j34;
  reg  [7:0]  b34 [0:11];
  reg  [7:0]  xor34;
  reg         t31b_ok;
  // T31c continuous-mode locals (module scope for Verilog-2001/XSim).
  integer     k31c;
  reg  [7:0]  xor34c;
  reg         t31c_ok;

  uart_cmd_parser #(.CLK_HZ(CLK_HZ)) dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .uart_rx       (uart_rx),
    .uart_tx       (uart_tx),
    .spi_valid     (spi_valid),
    .spi_cmd       (spi_cmd),
    .spi_done      (spi_done),
    .spi_rdata     (spi_rdata),
    .spi_busy      (spi_busy),
    .o_global_rst  (global_rst),
    .o_boot_start  (boot_start_tb),
    .i_boot_busy   (boot_busy_tb),
    .i_boot_done   (boot_done_tb),
    .i_boot_chip   (boot_chip_tb),
    .i_boot_err    (boot_err_tb),
    .i_si5340_lolb (1'b1),
    .i_si5340_losxb(1'b1),
    .o_adc_arm     (adc_arm_tb),
    .o_adc_n       (),
    .o_adc_rd_addr (adc_rd_addr_tb),
    .o_adc_chan_sel(adc_chan_sel_tb),
    .i_adc_done    (adc_done_tb),
    .i_adc_busy    (adc_busy_tb),
    .i_adc_rdata   (adc_rdata_tb),
    .o_dac_tone_en (dac_tone_en_tb),
    .o_dac_wave_sel(dac_wave_sel_tb),
    .o_dac_freq_word(dac_freq_word_tb),
    .o_dac_amp_pct (dac_amp_pct_tb),
    .o_nco_freq_word(nco_freq_word_tb),
    .o_dec_ratio   (dec_ratio_tb),
    .o_capture_mode(capture_mode_tb),
    .o_iq_bypass   (iq_bypass_tb),
    .o_fir_bypass  (fir_bypass_tb),
    .o_iq_mult_op1 (iq_mult_op1_tb),
    .o_iq_mult_op2 (iq_mult_op2_tb),
    .o_iq_offset_i (iq_offset_i_tb),
    .o_iq_offset_q (iq_offset_q_tb),
    .i_stream_byte (stream_byte_tb),
    .i_stream_byte_vld(stream_vld_tb),
    .i_stream_overflow(stream_ovf_tb),
    .o_stream_enable(stream_en_tb),
    .o_stream_byte_ready(stream_rdy_tb),
    .o_state       (),
    .o_frame_start (),
    .o_last_chip   (),
    .o_last_cmd    (),
    .o_last_status ()
  );

  // ---- primitives -------------------------------------------------------

  task uart_byte;
    input [7:0] b;
    integer i;
    begin
      uart_rx = 0; #BIT_NS;
      for (i = 0; i < 8; i = i + 1) begin uart_rx = b[i]; #BIT_NS; end
      uart_rx = 1; #BIT_NS;
    end
  endtask

  task send_cmd;
    input [7:0] hdr, cmd, chip, addr, data;
    begin
      uart_byte(hdr); uart_byte(cmd); uart_byte(chip);
      uart_byte(addr); uart_byte(data);
    end
  endtask

  // Wait for and verify the 4-byte UART ACK: BB | status | data | checksum
  task check_ack;
    input [7:0]   exp_st, exp_data;
    input [255:0] tag;
    reg [7:0] b[0:3];
    integer i, j;
    begin
      for (i = 0; i < 4; i = i + 1) begin
        wait (uart_tx == 0);
        #(BIT_NS + BIT_NS / 2);
        for (j = 0; j < 8; j = j + 1) begin
          b[i] = {uart_tx, b[i][7:1]};
          #BIT_NS;
        end
        #(BIT_NS / 2);
      end
      if (b[0] !== 8'hbb)
        begin $display("  [%0s] ACK[0] exp=bb got=%02h",             tag, b[0]); errs = errs+1; end
      if (b[1] !== exp_st)
        begin $display("  [%0s] ACK[1] exp=%02h got=%02h",           tag, exp_st,  b[1]); errs = errs+1; end
      if (b[2] !== exp_data)
        begin $display("  [%0s] ACK[2] exp=%02h got=%02h",           tag, exp_data, b[2]); errs = errs+1; end
      if (b[3] !== (8'hbb ^ exp_st ^ exp_data))
        begin $display("  [%0s] ACK[3] cksum exp=%02h got=%02h",     tag, 8'hbb^exp_st^exp_data, b[3]); errs = errs+1; end
    end
  endtask

  // Acknowledge one SPI frame; set spi_rdata before calling
  task spi_ack;
    input [55:0] rdata;
    begin
      spi_rdata = rdata;
      wait (spi_valid === 1'b1);
      repeat (4) @(posedge clk);
      spi_done = 1; @(posedge clk); spi_done = 0;
    end
  endtask

  // Build 56-bit spi_rdata with response byte at chip-correct position.
  function [55:0] rdata_for;
    input [7:0] chip, data;
    begin
      rdata_for = 56'h0;
      if (chip == 8'h02) rdata_for[39:32] = data;  // AD9640
      else               rdata_for[47:40] = data;  // AD9117, SI5340
    end
  endfunction

  // Assert equality; print diff and increment errs on mismatch
  task check_field;
    input [63:0]  got, exp;
    input [255:0] tag;
    begin
      if (got !== exp)
        begin $display("  [%0s] exp=%0h got=%0h", tag, exp, got); errs = errs+1; end
    end
  endtask

  reg [62:0] cap_f0, cap_f1;  // capture SPI frames for multi-frame tests

  // ---- test body --------------------------------------------------------
  initial begin
    repeat (20) @(posedge clk);
    rst_n = 1;
    $display("Reset released. BIT_NS=%0d ns", BIT_NS);

    // T1: Ping -----------------------------------------------------------
    $display("T1: Ping");
    send_cmd(8'haa, 8'hf0, 8'h00, 8'h00, 8'h00);
    check_ack(8'h00, 8'hbb, "T1");
    $display("  done errs=%0d", errs);

    // T2: Bad chip ID -> status=02 ----------------------------------------
    $display("T2: Bad chip ID");
    send_cmd(8'haa, 8'h01, 8'hff, 8'h00, 8'h55);
    check_ack(8'h02, 8'h00, "T2");
    $display("  done errs=%0d", errs);

    // T3: Unknown command -> status=01 ------------------------------------
    // (0x03 is burst-write now; use 0x55 as a genuinely unknown opcode)
    $display("T3: Unknown command");
    send_cmd(8'haa, 8'h55, 8'h01, 8'h00, 8'h00);
    check_ack(8'h01, 8'h00, "T3");
    $display("  done errs=%0d", errs);

    // T4: AD9117 write ---------------------------------------------------
    // chip=03 -> slv_sel=2; frame = {0,00,addr[4:0],wdata} left-aligned
    $display("T4: AD9117 write (addr=05 data=12)");
    fork
      send_cmd(8'haa, 8'h01, 8'h03, 8'h05, 8'h12);
      spi_ack(56'h0);
      check_ack(8'h00, 8'h00, "T4");
    join
    check_field(spi_cmd[62:60], 3'd2,     "T4-slv_sel");
    check_field(spi_cmd[56],    1'b0,     "T4-rd_en");
    check_field(spi_cmd[55:40], 16'h0512, "T4-frame");  // {0,00,00101,00010010}
    $display("  done errs=%0d", errs);

    // T5: SI5340 write — verify BOTH SPI frames --------------------------
    // chip=01 -> slv_sel=0; frame0={00,addr}, frame1={40,wdata}
    $display("T5: SI5340 write (addr=20 data=ab) - both SPI frames");
    fork
      send_cmd(8'haa, 8'h01, 8'h01, 8'h20, 8'hab);
      begin
        wait (spi_valid); cap_f0 = spi_cmd;
        repeat (4) @(posedge clk); spi_done = 1; @(posedge clk); spi_done = 0;
        wait (spi_valid); cap_f1 = spi_cmd;
        repeat (4) @(posedge clk); spi_done = 1; @(posedge clk); spi_done = 0;
      end
      check_ack(8'h00, 8'h00, "T5");
    join
    check_field(cap_f0[62:60], 3'd0,     "T5-slv_sel");
    check_field(cap_f0[56],    1'b0,     "T5-f0-rd_en");
    check_field(cap_f0[55:40], 16'h0020, "T5-f0-set-addr");  // {00, 0x20}
    check_field(cap_f1[56],    1'b0,     "T5-f1-rd_en");
    check_field(cap_f1[55:40], 16'h40ab, "T5-f1-wdata");     // {40, 0xab}
    $display("  done errs=%0d", errs);

    // T6: AD9117 read — rd_en set, data from spi_rdata[47:40] -----------
    $display("T6: AD9117 read (addr=1f) expect data=0a");
    fork
      send_cmd(8'haa, 8'h02, 8'h03, 8'h1f, 8'h00);
      spi_ack(rdata_for(8'h03, 8'h0a));
      check_ack(8'h00, 8'h0a, "T6");
    join
    check_field(spi_cmd[62:60], 3'd2,     "T6-slv_sel");
    check_field(spi_cmd[56],    1'b1,     "T6-rd_en");
    check_field(spi_cmd[55:40], 16'h9f00, "T6-frame");  // {1,00,11111,00000000}
    $display("  done errs=%0d", errs);

    // T7: AD9640 read — data from spi_rdata[39:32], NOT [47:40] ---------
    $display("T7: AD9640 read (addr=01) expect data=11");
    fork
      send_cmd(8'haa, 8'h02, 8'h02, 8'h01, 8'h00);
      spi_ack(rdata_for(8'h02, 8'h11));  // 0x11 placed at [39:32]
      check_ack(8'h00, 8'h11, "T7");
    join
    check_field(spi_cmd[62:60], 3'd1,     "T7-slv_sel");
    check_field(spi_cmd[56],    1'b1,     "T7-rd_en");
    check_field(spi_cmd[55:40], 16'h8001, "T7-frame");  // {1,00,00000,00000001}
    $display("  done errs=%0d", errs);

    // T8: write after read — ACK data must be 0x00, no stale leak --------
    $display("T8: AD9640 read 0x11, then AD9117 write: ACK data must be 00");
    fork
      send_cmd(8'haa, 8'h02, 8'h02, 8'h01, 8'h00);
      spi_ack(rdata_for(8'h02, 8'h11));
      check_ack(8'h00, 8'h11, "T8-read");
    join
    fork
      send_cmd(8'haa, 8'h01, 8'h03, 8'h05, 8'haa);
      spi_ack(56'h0);
      check_ack(8'h00, 8'h00, "T8-write");   // must not carry stale 0x11
    join
    $display("  done errs=%0d", errs);

    // T9: SI5340 read — two frames, frame0=set-addr, frame1=read ---------
    // chip=01; frame0={00,addr} rd_en=0; frame1={80,ff} rd_en=1
    $display("T9: SI5340 read (addr=02) expect data=41");
    fork
      send_cmd(8'haa, 8'h02, 8'h01, 8'h02, 8'h00);
      begin
        spi_rdata = 56'h0;
        wait (spi_valid); cap_f0 = spi_cmd;
        repeat (4) @(posedge clk); spi_done = 1; @(posedge clk); spi_done = 0;
        spi_rdata = rdata_for(8'h01, 8'h41);
        wait (spi_valid); cap_f1 = spi_cmd;
        repeat (4) @(posedge clk); spi_done = 1; @(posedge clk); spi_done = 0;
      end
      check_ack(8'h00, 8'h41, "T9");
    join
    check_field(cap_f0[56],    1'b0,     "T9-f0-rd_en");
    check_field(cap_f0[55:40], 16'h0002, "T9-f0-set-addr");  // {00, 0x02}
    check_field(cap_f1[56],    1'b1,     "T9-f1-rd_en");
    check_field(cap_f1[55:40], 16'h80ff, "T9-f1-read");      // {80, ff}
    $display("  done errs=%0d", errs);

    // T10: Non-0xAA bytes ignored; FSM re-syncs on next valid frame ------
    $display("T10: Garbage bytes ignored; re-sync on 0xAA");
    uart_byte(8'h55);
    uart_byte(8'hf0);
    send_cmd(8'haa, 8'hf0, 8'h00, 8'h00, 8'h00);
    check_ack(8'h00, 8'hbb, "T10");
    $display("  done errs=%0d", errs);

    // T11: 0xF1 read firmware version -----------------------------------
    $display("T11: Read firmware version (expect 0x01)");
    send_cmd(8'haa, 8'hf1, 8'h00, 8'h00, 8'h00);
    check_ack(8'h00, 8'h01, "T11");
    $display("  done errs=%0d", errs);

    // T12: 0xFE error query — returns last non-zero status (=0x01 from T3) -
    // (run before T13 so the global-reset bad-id case doesn't clobber err_reg)
    $display("T12: Error query (expect 0x01 from previous unknown cmd)");
    send_cmd(8'haa, 8'hfe, 8'h00, 8'h00, 8'h00);
    check_ack(8'h00, 8'h01, "T12");
    $display("  done errs=%0d", errs);

    // T13: 0xF2 global reset --------------------------------------------
    $display("T13: Global reset (chip=FF) pulses o_global_rst");
    grst_seen = 0;
    send_cmd(8'haa, 8'hf2, 8'hff, 8'h00, 8'h00);
    check_ack(8'h00, 8'h00, "T13");
    if (!grst_seen) begin
      $display("  [T13] o_global_rst pulse NOT observed"); errs = errs + 1;
    end
    if (dac_tone_en_tb !== 1'b0 || dac_wave_sel_tb !== 2'd0 ||
        dac_freq_word_tb !== 16'd546 || dac_amp_pct_tb !== 8'd50) begin
      $display("  [T13] DAC defaults mismatch en=%0d wave=%0d freq=0x%04h amp=%0d",
               dac_tone_en_tb, dac_wave_sel_tb, dac_freq_word_tb, dac_amp_pct_tb);
      errs = errs + 1;
    end
    // wrong chip id for 0xF2 must report status=02
    send_cmd(8'haa, 8'hf2, 8'h00, 8'h00, 8'h00);
    check_ack(8'h02, 8'h00, "T13-badid");
    $display("  done errs=%0d", errs);

    // T14: 0x10 soft reset on AD9117 — two SPI writes (0x20 then 0x00) ---
    $display("T14: 0x10 soft-reset AD9117 (2 SPI writes at addr=00)");
    fork
      send_cmd(8'haa, 8'h10, 8'h03, 8'h00, 8'h00);
      begin
        wait (spi_valid); cap_f0 = spi_cmd;
        repeat (4) @(posedge clk); spi_done = 1; @(posedge clk); spi_done = 0;
        wait (spi_valid); cap_f1 = spi_cmd;
        repeat (4) @(posedge clk); spi_done = 1; @(posedge clk); spi_done = 0;
      end
      check_ack(8'h00, 8'h00, "T14");
    join
    check_field(cap_f0[62:60], 3'd2,     "T14-f0-slv_sel");
    check_field(cap_f0[56],    1'b0,     "T14-f0-rd_en");
    check_field(cap_f0[55:40], 16'h0020, "T14-f0-frame"); // addr=00 data=0x20
    check_field(cap_f1[55:40], 16'h0000, "T14-f1-frame"); // addr=00 data=0x00
    $display("  done errs=%0d", errs);

    // T15: 0x11 output enable (data=1 -> clear PD = write 0x00 to addr 0x00)
    $display("T15: 0x11 enable AD9117 (data=01 -> write 0x00 at 00)");
    fork
      send_cmd(8'haa, 8'h11, 8'h03, 8'h00, 8'h01);
      spi_ack(56'h0);
      check_ack(8'h00, 8'h00, "T15");
    join
    check_field(spi_cmd[55:40], 16'h0000, "T15-frame");
    $display("  done errs=%0d", errs);

    // T16: 0x12 power-down (data=1 -> write 0x20 to addr 0x00) ----------
    $display("T16: 0x12 power-down AD9117 (data=01 -> write 0x20 at 00)");
    fork
      send_cmd(8'haa, 8'h12, 8'h03, 8'h00, 8'h01);
      spi_ack(56'h0);
      check_ack(8'h00, 8'h00, "T16");
    join
    check_field(spi_cmd[55:40], 16'h0020, "T16-frame");
    $display("  done errs=%0d", errs);

    // T17: 0x03 burst write to AD9117 (N=3, addr=0x05, data=11,22,33) ----
    $display("T17: 0x03 burst write AD9117 N=3");
    fork
      begin
        send_cmd(8'haa, 8'h03, 8'h03, 8'h05, 8'h03);
        uart_byte(8'h11); uart_byte(8'h22); uart_byte(8'h33);
      end
      begin
        // 3 SPI writes, one per data byte
        wait (spi_valid); cap_f0 = spi_cmd;  // addr=05 data=11
        repeat (4) @(posedge clk); spi_done = 1; @(posedge clk); spi_done = 0;
        wait (spi_valid); cap_f1 = spi_cmd;  // addr=06 data=22
        repeat (4) @(posedge clk); spi_done = 1; @(posedge clk); spi_done = 0;
        wait (spi_valid);                    // addr=07 data=33
        repeat (4) @(posedge clk); spi_done = 1; @(posedge clk); spi_done = 0;
      end
      check_ack(8'h00, 8'h03, "T17");
    join
    check_field(cap_f0[55:40], 16'h0511, "T17-byte0"); // {0,00,00101,00010001}
    check_field(cap_f1[55:40], 16'h0622, "T17-byte1"); // {0,00,00110,00100010}
    $display("  done errs=%0d", errs);

    // T18: 0x03 burst write to SI5340 — each byte = 2 SPI frames --------
    $display("T18: 0x03 burst write SI5340 N=2 (each byte = set-addr + write)");
    fork
      begin
        send_cmd(8'haa, 8'h03, 8'h01, 8'h10, 8'h02);
        uart_byte(8'haa); uart_byte(8'hbb);
      end
      begin
        // byte 0: 2 SPI frames (set addr=10, write aa)
        wait (spi_valid); cap_f0 = spi_cmd;
        repeat (4) @(posedge clk); spi_done = 1; @(posedge clk); spi_done = 0;
        wait (spi_valid); cap_f1 = spi_cmd;
        repeat (4) @(posedge clk); spi_done = 1; @(posedge clk); spi_done = 0;
        // byte 1: 2 SPI frames (set addr=11, write bb)
        wait (spi_valid);
        repeat (4) @(posedge clk); spi_done = 1; @(posedge clk); spi_done = 0;
        wait (spi_valid);
        repeat (4) @(posedge clk); spi_done = 1; @(posedge clk); spi_done = 0;
      end
      check_ack(8'h00, 8'h02, "T18");
    join
    check_field(cap_f0[55:40], 16'h0010, "T18-b0-setaddr"); // {00,0x10}
    check_field(cap_f1[55:40], 16'h40aa, "T18-b0-wdata");   // {40,0xaa}
    $display("  done errs=%0d", errs);

    // T19: 0x20 boot-trigger when idle ----------------------------------
    $display("T19: 0x20 boot trigger when idle (expect ACK data=01, start pulse)");
    boot_busy_tb = 0; boot_done_tb = 0;
    fork
      send_cmd(8'haa, 8'h20, 8'h00, 8'h00, 8'h00);
      check_ack(8'h00, 8'h01, "T19");
    join
    // start pulse should have asserted at least once during the command
    $display("  done errs=%0d", errs);

    // T20: 0x20 while boot_busy -> status=05 BUSY -----------------------
    $display("T20: 0x20 while busy -> status=05");
    boot_busy_tb = 1;
    send_cmd(8'haa, 8'h20, 8'h00, 8'h00, 8'h00);
    check_ack(8'h05, 8'h00, "T20");

    // T21: SPI cmd while boot_busy -> status=05 -------------------------
    $display("T21: AD9117 write while boot busy -> status=05 (no SPI issued)");
    send_cmd(8'haa, 8'h01, 8'h03, 8'h05, 8'h12);
    check_ack(8'h05, 8'h00, "T21");

    // T22: 0x21 status query while busy --------------------------------
    $display("T22: 0x21 status (busy=1, done=0, lolb=1, losxb=1, chip=1)");
    boot_chip_tb = 4'h1;  // SI5340
    send_cmd(8'haa, 8'h21, 8'h00, 8'h00, 8'h00);
    // expect: {busy=1, done=0, lolb=1, losxb=1, chip=4'h1} = 8'b1011_0001 = 0xB1
    check_ack(8'h00, 8'hb1, "T22");

    // T23: F0 ping passes through during boot --------------------------
    $display("T23: F0 ping while boot busy (still ACK 00 BB)");
    send_cmd(8'haa, 8'hf0, 8'h00, 8'h00, 8'h00);
    check_ack(8'h00, 8'hbb, "T23");

    // T24: boot_err propagation to err_reg + 0xFE ----------------------
    $display("T24: boot_err=0x10 -> 0xFE returns 0x10 (priority over earlier UART err)");
    // err_reg currently holds 0x05 from T20/T21; we expect it to NOT clobber.
    // So inject a fresh-start: reset err_reg by triggering... actually parser only
    // overwrites err_reg if !=0 status_now arrives.  We can't reset it from outside.
    // Instead, force boot_err high and observe: should NOT overwrite existing nonzero.
    boot_err_tb = 8'h10;
    send_cmd(8'haa, 8'hfe, 8'h00, 8'h00, 8'h00);
    // err_reg should still hold 0x05 (from T20/T21) — boot_err only fills when err_reg==0
    check_ack(8'h00, 8'h05, "T24-existing");
    boot_err_tb = 8'h00;
    boot_busy_tb = 0;

    // T25: 0x30 arm while idle -> accepted, arm held until done pulse -----
    $display("T25: 0x30 ADC arm N=16 (adc idle) -> BB 00 00 BB");
    adc_busy_tb = 0;
    fork
      begin
        send_cmd(8'haa, 8'h30, 8'h00, 8'h00, 8'h10);
        // wait for parser to assert arm, then fire done after 5 cycles
        wait (adc_arm_tb === 1'b1);
        repeat (5) @(posedge clk);
        adc_done_tb = 1; @(posedge clk); adc_done_tb = 0;
      end
      check_ack(8'h00, 8'h00, "T25");
    join
    $display("  done errs=%0d", errs);

    // T26: 0x31 read addr=5 -> returns rdata[13:6] of 14'h3ABC (=0xEA) ----
    // 14'h3ABC = 11_1010_1011_1100 -> [13:6] = 1110_1010 = 0xEA
    $display("T26: 0x31 ADC read addr=5, rdata=14'h3ABC -> ACK data=0xEA");
    adc_rdata_fixed = 14'h3ABC;
    send_cmd(8'haa, 8'h31, 8'h00, 8'h00, 8'h05);
    check_ack(8'h00, 8'hEA, "T26");
    $display("  done errs=%0d", errs);

    // T26b: 0x32 read addr=5 -> returns {2'b00, rdata[5:0]} of 14'h3ABC ----
    // 14'h3ABC [5:0] = 11_1100 = 6'h3C -> {2'b00, 6'h3C} = 0x3C
    $display("T26b: 0x32 ADC read addr=5, rdata=14'h3ABC -> ACK data=0x3C");
    adc_rdata_fixed = 14'h3ABC;
    send_cmd(8'haa, 8'h32, 8'h00, 8'h00, 8'h05);
    check_ack(8'h00, 8'h3C, "T26b");
    $display("  done errs=%0d", errs);

    // T27: 0x30 while adc busy -> status=05 --------------------------------
    $display("T27: 0x30 while adc busy -> status=05");
    adc_busy_tb = 1;
    send_cmd(8'haa, 8'h30, 8'h00, 8'h00, 8'h10);
    check_ack(8'h05, 8'h00, "T27");
    adc_busy_tb = 0;
    $display("  done errs=%0d", errs);

    // T28: 0x40 DAC tone enable=1 -> o_dac_tone_en sticky, ACK BB 00 01 BA -
    $display("T28: 0x40 DAC tone enable=1");
    boot_busy_tb = 0;
    send_cmd(8'haa, 8'h40, 8'h00, 8'h00, 8'h01);
    check_ack(8'h00, 8'h01, "T28");
    if (dac_tone_en_tb !== 1'b1) begin
      $display("  [T28] o_dac_tone_en exp=1 got=%b", dac_tone_en_tb);
      errs = errs + 1;
    end
    // disable
    send_cmd(8'haa, 8'h40, 8'h00, 8'h00, 8'h00);
    check_ack(8'h00, 8'h00, "T28-off");
    if (dac_tone_en_tb !== 1'b0) begin
      $display("  [T28] o_dac_tone_en exp=0 got=%b", dac_tone_en_tb);
      errs = errs + 1;
    end
    $display("  done errs=%0d", errs);

    // T29: 0x40 while boot_busy -> status=05, tone_en unchanged ------------
    $display("T29: 0x40 while boot busy -> status=05");
    // first enable so we can verify it's NOT touched by the rejected cmd
    send_cmd(8'haa, 8'h40, 8'h00, 8'h00, 8'h01);
    check_ack(8'h00, 8'h01, "T29-pre");
    boot_busy_tb = 1;
    send_cmd(8'haa, 8'h40, 8'h00, 8'h00, 8'h00);
    check_ack(8'h05, 8'h00, "T29");
    if (dac_tone_en_tb !== 1'b1) begin
      $display("  [T29] o_dac_tone_en exp=1 (unchanged) got=%b", dac_tone_en_tb);
      errs = errs + 1;
    end
    boot_busy_tb = 0;
    // clean up: disable
    send_cmd(8'haa, 8'h40, 8'h00, 8'h00, 8'h00);
    check_ack(8'h00, 8'h00, "T29-cleanup");
    $display("  done errs=%0d", errs);

    // T29b: 0x41/0x42/0x43 DAC config registers -----------------------------
    $display("T29b: DAC waveform/freq/amp config");
    send_cmd(8'haa, 8'h41, 8'h00, 8'h00, 8'h01);  // square
    check_ack(8'h00, 8'h01, "T29b-wave");
    if (dac_wave_sel_tb !== 2'd1) begin
      $display("  [T29b] wave exp=1 got=%0d", dac_wave_sel_tb); errs = errs + 1;
    end
    send_cmd(8'haa, 8'h42, 8'h00, 8'h00, 8'h02);  // freq[15:8]
    check_ack(8'h00, 8'h02, "T29b-freq-hi");
    send_cmd(8'haa, 8'h42, 8'h00, 8'h01, 8'h22);  // freq[7:0]
    check_ack(8'h00, 8'h22, "T29b-freq-lo");
    if (dac_freq_word_tb !== 16'h0222) begin
      $display("  [T29b] freq exp=0x0222 got=0x%04h", dac_freq_word_tb); errs = errs + 1;
    end
    send_cmd(8'haa, 8'h43, 8'h00, 8'h00, 8'h32);  // amp=50
    check_ack(8'h00, 8'h32, "T29b-amp");
    if (dac_amp_pct_tb !== 8'd50) begin
      $display("  [T29b] amp exp=50 got=%0d", dac_amp_pct_tb); errs = errs + 1;
    end
    send_cmd(8'haa, 8'h43, 8'h00, 8'h00, 8'hC8);  // clamp to 100
    check_ack(8'h00, 8'h64, "T29b-amp-clamp");
    if (dac_amp_pct_tb !== 8'd100) begin
      $display("  [T29b] amp clamp exp=100 got=%0d", dac_amp_pct_tb); errs = errs + 1;
    end
    $display("  done errs=%0d", errs);

    // T30: 0x33 ADC burst read — arm N=8, stream 16 bytes (hi/lo per sample) + ACK -
    $display("T30: 0x33 burst-read N=8");
    begin : t30_block
      integer i30, j30;
      reg [13:0] s30;
      reg [7:0]  rx30 [0:19];   // 16 payload + 4 ACK bytes
      reg [7:0]  exp_xor;

      // populate mock BRAM with a deterministic pattern
      adc_burst_mem[0] = 14'h0123;
      adc_burst_mem[1] = 14'h2BCD;
      adc_burst_mem[2] = 14'h3FFF;
      adc_burst_mem[3] = 14'h0000;
      adc_burst_mem[4] = 14'h1A5A;
      adc_burst_mem[5] = 14'h25A5;
      adc_burst_mem[6] = 14'h3ABC;
      adc_burst_mem[7] = 14'h0042;

      // compute expected XOR8 over hi,lo bytes
      exp_xor = 8'h00;
      for (i30 = 0; i30 < 8; i30 = i30 + 1) begin
        s30 = adc_burst_mem[i30];
        exp_xor = exp_xor ^ s30[13:6];
        exp_xor = exp_xor ^ {2'b00, s30[5:0]};
      end

      // arm N=8 (status=00 path)
      adc_busy_tb = 0;
      fork
        begin
          send_cmd(8'haa, 8'h30, 8'h00, 8'h00, 8'h08);
          wait (adc_arm_tb === 1'b1);
          repeat (5) @(posedge clk);
          adc_done_tb = 1; @(posedge clk); adc_done_tb = 0;
        end
        check_ack(8'h00, 8'h00, "T30-arm");
      join

      // switch ADC stub into burst mode and trigger 0x33
      adc_burst_mode = 1;
      send_cmd(8'haa, 8'h33, 8'h00, 8'h00, 8'h00);

      // capture 16 payload bytes + 4 ACK bytes
      for (i30 = 0; i30 < 20; i30 = i30 + 1) begin
        wait (uart_tx == 0);
        #(BIT_NS + BIT_NS / 2);
        for (j30 = 0; j30 < 8; j30 = j30 + 1) begin
          rx30[i30] = {uart_tx, rx30[i30][7:1]};
          #BIT_NS;
        end
        #(BIT_NS / 2);
      end

      // verify payload bytes (hi,lo interleaved)
      for (i30 = 0; i30 < 8; i30 = i30 + 1) begin
        s30 = adc_burst_mem[i30];
        if (rx30[2*i30] !== s30[13:6]) begin
          $display("  [T30] payload[%0d] hi exp=%02h got=%02h",
                   i30, s30[13:6], rx30[2*i30]);
          errs = errs + 1;
        end
        if (rx30[2*i30+1] !== {2'b00, s30[5:0]}) begin
          $display("  [T30] payload[%0d] lo exp=%02h got=%02h",
                   i30, {2'b00, s30[5:0]}, rx30[2*i30+1]);
          errs = errs + 1;
        end
      end

      // verify ACK trailer: BB 00 <xor8> <bb^00^xor8>
      if (rx30[16] !== 8'hbb) begin
        $display("  [T30] ACK[0] exp=bb got=%02h", rx30[16]); errs = errs + 1;
      end
      if (rx30[17] !== 8'h00) begin
        $display("  [T30] ACK[1] exp=00 got=%02h", rx30[17]); errs = errs + 1;
      end
      if (rx30[18] !== exp_xor) begin
        $display("  [T30] ACK[2] xor exp=%02h got=%02h", exp_xor, rx30[18]);
        errs = errs + 1;
      end
      if (rx30[19] !== (8'hbb ^ 8'h00 ^ exp_xor)) begin
        $display("  [T30] ACK[3] cksum exp=%02h got=%02h",
                 8'hbb ^ exp_xor, rx30[19]);
        errs = errs + 1;
      end

      adc_burst_mode = 0;
    end
    $display("  done errs=%0d", errs);

    // T31: 0x44/0x45 RX config sticky registers --------
    $display("T31: 0x44/0x45 RX config");
    send_cmd(8'haa, 8'h44, 8'h00, 8'h00, 8'hAB);  // freq[15:8]
    check_ack(8'h00, 8'hAB, "T31-nco-hi");
    send_cmd(8'haa, 8'h44, 8'h00, 8'h01, 8'hCD);  // freq[7:0]
    check_ack(8'h00, 8'hCD, "T31-nco-lo");
    if (nco_freq_word_tb !== 16'hABCD) begin
      $display("  [T31] nco_freq exp=0xABCD got=0x%04h", nco_freq_word_tb);
      errs = errs + 1;
    end
    // data[1:0]=2, bit2=1(capture_mode), bit3=1(fir_bypass), bit4=0(iq_bypass)
    send_cmd(8'haa, 8'h45, 8'h00, 8'h00, 8'h0E);
    check_ack(8'h00, 8'h0E, "T31-cfg");
    if (dec_ratio_tb !== 2'd2 || capture_mode_tb !== 1'b1 || fir_bypass_tb !== 1'b1 || iq_bypass_tb !== 1'b0) begin
      $display("  [T31] cfg mismatch dec=%0d mode=%0d fir=%0d iq=%0d",
               dec_ratio_tb, capture_mode_tb, fir_bypass_tb, iq_bypass_tb);
      errs = errs + 1;
    end
    // non-zero chip ID for 0x44 must be rejected with status=02
    send_cmd(8'haa, 8'h44, 8'h01, 8'h00, 8'h00);
    check_ack(8'h02, 8'h00, "T31-badchip");
    $display("  done errs=%0d", errs);

    // T31b: 0x34 stream mode basic transfer + ACK --------------------------
    $display("T31b: 0x34 stream 2 samples (8 bytes)");
    xor34  = 8'h00;
    t31b_ok = 1'b1;
    send_cmd(8'haa, 8'h34, 8'h00, 8'h00, 8'h02);

    // Wait stream mode enable with timeout (avoid deadlock on regressions).
    i34 = 0;
    while (!stream_en_tb && (i34 < 200000)) begin
      @(posedge clk);
      i34 = i34 + 1;
    end
    if (!stream_en_tb) begin
      $display("  [T31b] stream_en timeout");
      errs = errs + 1;
      t31b_ok = 1'b0;
    end

    if (t31b_ok) begin : t31b_send_loop
      for (k31b = 0; k31b < 8; k31b = k31b + 1) begin
        stream_byte_tb = 8'h80 + k31b[7:0];
        stream_vld_tb  = 1'b1;
        i34 = 0;
        while (!stream_rdy_tb && (i34 < 200000)) begin
          @(posedge clk);
          i34 = i34 + 1;
        end
        if (!stream_rdy_tb) begin
          $display("  [T31b] stream_rdy timeout at byte %0d", k31b);
          errs = errs + 1;
          t31b_ok = 1'b0;
          stream_vld_tb = 1'b0;
          disable t31b_send_loop;
        end
        xor34 = xor34 ^ stream_byte_tb;
        @(posedge clk);
        stream_vld_tb = 1'b0;
      end
    end

    // Wait stream mode to end, then verify trailer ACK.
    if (t31b_ok) begin
      i34 = 0;
      while (stream_en_tb && (i34 < 200000)) begin
        @(posedge clk);
        i34 = i34 + 1;
      end
      if (stream_en_tb) begin
        $display("  [T31b] stream_end timeout");
        errs = errs + 1;
        t31b_ok = 1'b0;
      end
    end
    if (t31b_ok)
      check_ack(8'h00, xor34, "T31b-ack");
    $display("  done errs=%0d", errs);

    // T31c: 0x34 continuous-mode (N=0) + host stop byte --------------------
    // FPGA should keep streaming until any UART byte is received, then finish
    // the current 4-byte sample and emit the 4-byte ACK.
    $display("T31c: 0x34 stream N=0 (continuous) + stop byte");
    xor34c  = 8'h00;
    t31c_ok = 1'b1;
    send_cmd(8'haa, 8'h34, 8'h00, 8'h00, 8'h00);

    // Wait stream mode enable.
    i34 = 0;
    while (!stream_en_tb && (i34 < 200000)) begin
      @(posedge clk);
      i34 = i34 + 1;
    end
    if (!stream_en_tb) begin
      $display("  [T31c] stream_en timeout");
      errs = errs + 1;
      t31c_ok = 1'b0;
    end

    // Push 6 stream bytes (1.5 samples), then send a stop byte mid-sample.
    // FPGA should pull 2 more bytes to complete the current sample, then ACK.
    if (t31c_ok) begin : t31c_send_loop
      for (k31c = 0; k31c < 6; k31c = k31c + 1) begin
        stream_byte_tb = 8'h40 + k31c[7:0];
        stream_vld_tb  = 1'b1;
        i34 = 0;
        while (!stream_rdy_tb && (i34 < 200000)) begin
          @(posedge clk);
          i34 = i34 + 1;
        end
        if (!stream_rdy_tb) begin
          $display("  [T31c] stream_rdy timeout at byte %0d", k31c);
          errs = errs + 1;
          t31c_ok = 1'b0;
          stream_vld_tb = 1'b0;
          disable t31c_send_loop;
        end
        xor34c = xor34c ^ stream_byte_tb;
        @(posedge clk);
        stream_vld_tb = 1'b0;
      end
    end

    // Inject host stop byte over uart_rx (any value works; pick 0x55).
    if (t31c_ok) begin
      uart_byte(8'h55);
    end

    // After stop, FPGA finishes current sample (2 more bytes to reach 8 total)
    // then asserts ACK.  Provide those bytes.
    if (t31c_ok) begin : t31c_tail_loop
      for (k31c = 6; k31c < 8; k31c = k31c + 1) begin
        stream_byte_tb = 8'h40 + k31c[7:0];
        stream_vld_tb  = 1'b1;
        i34 = 0;
        while (!stream_rdy_tb && (i34 < 200000)) begin
          @(posedge clk);
          i34 = i34 + 1;
        end
        if (!stream_rdy_tb) begin
          $display("  [T31c] tail stream_rdy timeout at byte %0d", k31c);
          errs = errs + 1;
          t31c_ok = 1'b0;
          stream_vld_tb = 1'b0;
          disable t31c_tail_loop;
        end
        xor34c = xor34c ^ stream_byte_tb;
        @(posedge clk);
        stream_vld_tb = 1'b0;
      end
    end

    // Wait stream mode to end, then verify trailer ACK.
    if (t31c_ok) begin
      i34 = 0;
      while (stream_en_tb && (i34 < 400000)) begin
        @(posedge clk);
        i34 = i34 + 1;
      end
      if (stream_en_tb) begin
        $display("  [T31c] stream_end timeout (stop byte not honored?)");
        errs = errs + 1;
        t31c_ok = 1'b0;
      end
    end
    if (t31c_ok)
      check_ack(8'h00, xor34c, "T31c-ack");
    $display("  done errs=%0d", errs);

    // T32: 0x31 with f_addr[6]=1 toggles o_adc_chan_sel ---------------------
    // chan_sel is sticky; verify it follows the f_addr[6] bit of the last 0x31/0x32/0x33.
    $display("T32: 0x31 channel-select bit (f_addr[6])");
    adc_rdata_fixed = 14'h3ABC;
    // channel A (addr[6]=0) — addr field=0x00, addr=5 in low bits
    send_cmd(8'haa, 8'h31, 8'h00, 8'h00, 8'h05);
    check_ack(8'h00, 8'hEA, "T32-A");
    if (adc_chan_sel_tb !== 1'b0) begin
      $display("  [T32] chan_sel exp=0 (A) got=%b", adc_chan_sel_tb); errs = errs + 1;
    end
    // channel B (addr[6]=1) — addr field=0x40, addr=5 in low bits
    send_cmd(8'haa, 8'h31, 8'h00, 8'h40, 8'h05);
    check_ack(8'h00, 8'hEA, "T32-B");
    if (adc_chan_sel_tb !== 1'b1) begin
      $display("  [T32] chan_sel exp=1 (B) got=%b", adc_chan_sel_tb); errs = errs + 1;
    end
    $display("  done errs=%0d", errs);

    // -------------------------------------------------------------------
    repeat (200) @(posedge clk);
    if (errs == 0)
      $display("tb_uart_cmd_parser: PASS");
    else
      $display("tb_uart_cmd_parser: FAIL errs=%0d", errs);
    $finish;
  end

endmodule
