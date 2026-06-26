`timescale 1ns / 1ps

// Testbench for tx_iq_dsp (2x interpolation + 16->14 reduction spine).
//
// Latency-independent checks:
//   1. DC through-chain: const s14-ranged in -> 14-bit out == saturate(in) to
//      the 14-bit range (interpolator is exact unity DC, baseband is already
//      14-bit so the narrow is 1:1; validates sign/saturation/no /4).
//   2. Sine: 14-bit output stays within the 14-bit range with only the expected
//      small interpolation overshoot (catches sign/shift/saturation bugs).
//
// XSim: top = tb_tx_iq_dsp, Run Behavioral Simulation, run -all, expect
// "tb_tx_iq_dsp: PASS".
module tb_tx_iq_dsp;
  reg                clk = 0, rst_n = 0, in_vld = 0;
  reg  signed [15:0] din_i = 0, din_q = 0;
  wire               o_vld;
  wire signed [13:0] o_i, o_q;

  always #4 clk = ~clk;

  tx_iq_dsp dut (
    .i_clk(clk), .i_rst_n(rst_n),
    .i_in_vld(in_vld), .i_hb_bypass(1'b0), .i_dc_test(1'b0),
    .i_i(din_i), .i_q(din_q),
    .o_vld(o_vld), .o_i(o_i), .o_q(o_q)
  );

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) in_vld <= 1'b0;
    else        in_vld <= ~in_vld;
  end

  integer errs = 0;

  // expected signed 16->14 narrow: saturate to the 14-bit range, no down-shift
  function signed [13:0] exp14;
    input signed [15:0] s;
    begin
      if      (s >  16'sd8191) exp14 = 14'sh1FFF;
      else if (s < -16'sd8192) exp14 = 14'sh2000;
      else                      exp14 = s[13:0];
    end
  endfunction

  task test_dc;
    input signed [15:0] val;
    integer m; reg signed [13:0] want;
    begin
      din_i = val; din_q = -val; want = exp14(val);
      repeat (50) @(posedge clk);
      for (m = 0; m < 30; m = m + 1) begin
        @(posedge clk);
        if (o_vld) begin
          if ((o_i > want + 1) || (o_i < want - 1)) begin
            errs = errs + 1;
            $display("  FAIL DC I: in=%0d out=%0d want=%0d", val, o_i, want);
          end
        end
      end
      $display("  ok  DC in=%0d -> ~%0d", val, want);
    end
  endtask

  real    ph;
  integer amp = 7500, peak;
  task test_sine;
    integer m;
    begin
      ph = 0.0; peak = 0;
      repeat (60) @(posedge clk);
      for (m = 0; m < 4000; m = m + 1) begin
        @(posedge clk);
        if (in_vld) begin
          ph = ph + 0.20;
          din_i = $rtoi(amp * $sin(ph));
          din_q = $rtoi(amp * $cos(ph));
        end
        if (o_vld) begin
          if (o_i > peak)  peak = o_i;
          if (-o_i > peak) peak = -o_i;
        end
      end
      // s14-direct: peak ~= amp (7500); allow interp overshoot, must stay < 8191 FS
      if (peak > 8191) begin
        errs = errs + 1; $display("  FAIL sine clipped: peak=%0d", peak);
      end else if (peak < 7000) begin
        errs = errs + 1; $display("  FAIL sine low: peak=%0d (expect ~7500)", peak);
      end else
        $display("  ok  sine peak=%0d (expect ~7500, FS 8191)", peak);
    end
  endtask

  initial begin
    repeat (4) @(posedge clk);
    rst_n = 1; @(posedge clk);
    test_dc(16'sd5000);     // -> ~5000 (1:1)
    test_dc(-16'sd3000);    // -> ~-3000 (1:1)
    test_sine;
    if (errs == 0) $display("tb_tx_iq_dsp: PASS");
    else           $display("tb_tx_iq_dsp: FAIL errs=%0d", errs);
    $finish;
  end
endmodule
