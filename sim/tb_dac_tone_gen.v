`timescale 1ns / 1ps

// Testbench for rf_ctrl_path/dac_tone_gen.v (parallel 16-bit I/Q @ 61.44 MSa/s/ch).
module tb_dac_tone_gen;

  localparam integer CLK_PERIOD = 52;

  reg         clk      = 0;
  reg         rst_n    = 0;
  reg         tone_en  = 0;
  reg  [1:0]  wave_sel = 2'd0;
  reg  [15:0] freq_word = 16'd85;
  reg  [7:0]  amp_pct = 8'd50;
  wire signed [15:0] iq_i, iq_q;
  wire        iq_vld;

  integer errs = 0;

  always #(CLK_PERIOD / 2) clk = ~clk;

  dac_tone_gen dut (
    .i_clk     (clk),
    .i_rst_n   (rst_n),
    .i_tone_en (tone_en),
    .i_wave_sel(wave_sel),
    .i_freq_word(freq_word),
    .i_amp_pct (amp_pct),
    .o_iq_i16  (iq_i),
    .o_iq_q16  (iq_q),
    .o_iq_vld  (iq_vld)
  );

  initial begin
    #50_000_000;
    $display("[WATCHDOG] TIMEOUT errs=%0d", errs);
    $display("tb_dac_tone_gen: FAIL (timeout)");
    $finish;
  end

  task check;
    input        cond;
    input [255:0] tag;
    begin
      if (!cond) begin
        $display("  [%0s] FAIL @ t=%0t i=%0d q=%0d vld=%b", tag, $time, iq_i, iq_q, iq_vld);
        errs = errs + 1;
      end
    end
  endtask

  integer    i;
  integer    min_v;
  integer    max_v;
  integer    low_swing;
  integer    vld_count;
  integer    square_mid;
  integer    tri_mid;

  initial begin
    repeat (10) @(posedge clk);

    $display("T1: reset state");
    check(iq_i === 16'sd0, "T1-i");
    check(iq_q === 16'sd0, "T1-q");
    check(iq_vld === 1'b0, "T1-vld");

    rst_n = 1;
    @(posedge clk);
    repeat (4) @(posedge clk);
    check(iq_vld === 1'b0, "T1b-vld");

    $display("T2: tone_en=1 -> o_iq_vld every 2 cycles");
    @(negedge clk);
    tone_en = 1;
    repeat (20) @(posedge clk);
    vld_count = 0;
    for (i = 0; i < 40; i = i + 1) begin
      @(posedge clk); #1;
      if (iq_vld) vld_count = vld_count + 1;
    end
    check(vld_count >= 18 && vld_count <= 22, "T2-vld-half-rate");
    $display("  vld %0d / 40 cycles, errs=%0d", vld_count, errs);

    // Shape tests at full scale: amp scaling maps ±8191 rails to ~±8191;
    // "interior" = |sample| well below rail (±4095 @ 50% amp used to false-fail here).
    $display("T3: wave_sel=square -> rails only");
    amp_pct = 8'd100;
    wave_sel = 2'd1;
    repeat (30) @(posedge clk);
    square_mid = 0;
    for (i = 0; i < 64; i = i + 1) begin
      @(posedge clk); #1;
      if (iq_vld && (iq_i > -16'sd6000) && (iq_i < 16'sd6000))
        square_mid = square_mid + 1;
    end
    check(square_mid <= 4, "T3-square-rails-only");

    $display("T3b: wave_sel=triangle -> high mid-band");
    wave_sel = 2'd2;
    repeat (30) @(posedge clk);
    tri_mid = 0;
    for (i = 0; i < 64; i = i + 1) begin
      @(posedge clk); #1;
      if (iq_vld && (iq_i > -16'sd6000) && (iq_i < 16'sd6000))
        tri_mid = tri_mid + 1;
    end
    check(tri_mid > square_mid + 8, "T3b-tri-more-midband");

    $display("T4: amplitude scaling");
    wave_sel = 2'd0;
    amp_pct = 8'd25;
    repeat (10) @(posedge clk);
    min_v = 65536; max_v = -65536;
    for (i = 0; i < 120; i = i + 1) begin
      @(posedge clk); #1;
      if (iq_vld) begin
        if (iq_i < min_v) min_v = iq_i;
        if (iq_i > max_v) max_v = iq_i;
      end
    end
    low_swing = max_v - min_v;
    amp_pct = 8'd100;
    repeat (10) @(posedge clk);
    min_v = 65536; max_v = -65536;
    for (i = 0; i < 120; i = i + 1) begin
      @(posedge clk); #1;
      if (iq_vld) begin
        if (iq_i < min_v) min_v = iq_i;
        if (iq_i > max_v) max_v = iq_i;
      end
    end
    check((max_v - min_v) > low_swing, "T4-swing-grows-with-amp");

    $display("T5: tone_en=0 -> parked");
    @(negedge clk);
    tone_en = 0;
    repeat (20) @(posedge clk); #1;
    check(iq_i === 16'sd0, "T5-i");
    check(iq_vld === 1'b0, "T5-vld");

    repeat (20) @(posedge clk);
    if (errs == 0) $display("tb_dac_tone_gen: PASS");
    else           $display("tb_dac_tone_gen: FAIL errs=%0d", errs);
    $finish;
  end

endmodule
