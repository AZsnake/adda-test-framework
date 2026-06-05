`timescale 1ns / 1ps

// Testbench for tx_halfband_interp2 (2x polyphase halfband DAC interpolator).
//
// Checks (latency-independent so group delay doesn't matter):
//   1. DC unity gain: constant input -> every output equals it (validates the
//      Q15 coeffs + >>14 gain restore; a wrong coeff sum shows as a DC error).
//   2. Sine: no output overshoots the input amplitude beyond a small margin.
//      (guards against sign/shift/saturation bugs and instability).
//
// XSim: set top to tb_tx_halfband_interp2, Run Behavioral Simulation, run -all,
// look for "tb_tx_halfband_interp2: PASS".
module tb_tx_halfband_interp2;
  reg                clk = 0;
  reg                rst_n = 0;
  reg                in_vld = 0;
  reg  signed [15:0] din_i = 0, din_q = 0;
  wire               o_vld;
  wire signed [15:0] o_i, o_q;

  always #4 clk = ~clk;   // 125 MHz approx

  tx_halfband_interp2 dut (
    .i_clk(clk), .i_rst_n(rst_n),
    .i_in_vld(in_vld), .i_i(din_i), .i_q(din_q),
    .o_vld(o_vld), .o_i(o_i), .o_q(o_q)
  );

  integer errs = 0;
  integer n;

  // in_vld toggles every cycle -> one input sample every 2 cycles (61.44/ch).
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) in_vld <= 1'b0;
    else        in_vld <= ~in_vld;
  end

  // ---- Test 1: DC unity gain ----
  task test_dc;
    input signed [15:0] val;
    integer m;
    begin
      din_i = val; din_q = -val;
      // prime the line, then check a window of outputs
      repeat (40) @(posedge clk);
      for (m = 0; m < 30; m = m + 1) begin
        @(posedge clk);
        if (o_vld) begin
          if ((o_i > val + 1) || (o_i < val - 1)) begin
            errs = errs + 1;
            $display("  FAIL DC I: in=%0d out=%0d", val, o_i);
          end
          if ((o_q > -val + 1) || (o_q < -val - 1)) begin
            errs = errs + 1;
            $display("  FAIL DC Q: in=%0d out=%0d", -val, o_q);
          end
        end
      end
      $display("  ok  DC test val=%0d", val);
    end
  endtask

  // ---- Test 3: sine overshoot bound ----
  real    ph;
  integer amp = 8000;
  integer peak;
  task test_sine_bound;
    integer m;
    begin
      ph = 0.0; peak = 0;
      repeat (60) @(posedge clk);          // prime
      for (m = 0; m < 4000; m = m + 1) begin
        @(posedge clk);
        if (in_vld) begin
          ph = ph + 0.20;                  // ~ f0=0.1 of input Nyquist
          din_i = $rtoi(amp * $sin(ph));
          din_q = $rtoi(amp * $cos(ph));
        end
        if (o_vld) begin
          if (o_i > peak)  peak = o_i;
          if (-o_i > peak) peak = -o_i;
        end
      end
      // Interpolation legitimately reconstructs inter-sample peaks above the
      // discrete sample peaks (true continuous peak falls between input samples),
      // so allow ~8% over the sampled amplitude; this still catches sign/shift/
      // saturation bugs (which blow the peak far past that).
      if (peak > (amp * 108) / 100) begin
        errs = errs + 1;
        $display("  FAIL sine overshoot: peak=%0d amp=%0d", peak, amp);
      end else
        $display("  ok  sine bound: peak=%0d (amp=%0d)", peak, amp);
    end
  endtask

  // ---- Test 4: image rejection ----
  // Drive a complex tone at f0 = 0.13 * input-Nyquist (= 0.065 cyc/output-sample
  // at the full 2x rate).  A correct 2x halfband pushes the Fs1-f0 image deep;
  // a polyphase-alignment bug (FIR sampled a cycle after the delay line shifts)
  // leaves it ~ -7 dBc.  Single-bin DFTs over an integer number of cycles
  // (no leakage) at the carrier (0.065) and image (0.435) bins measure it.
  localparam real PI = 3.14159265358979;
  localparam real F0_IN  = 0.13;    // cyc / input-sample
  localparam real F0_OUT = 0.065;   // cyc / output-sample (full rate)
  localparam real FIMG   = 0.435;   // Fs1 - f0 image bin, cyc / output-sample
  localparam integer NWIN = 2000;   // 130 carrier cycles / 870 image cycles -> integer
  real cr_re, cr_im, im_re, im_im, ph2, w, mag_c, mag_i, img_dbc;
  integer k;
  task test_image_rejection;
    begin
      ph2 = 0.0;
      cr_re = 0.0; cr_im = 0.0; im_re = 0.0; im_im = 0.0;
      repeat (80) @(posedge clk);   // prime the line / flush transient
      for (k = 0; k < NWIN; ) begin
        @(posedge clk);
        if (in_vld) begin
          ph2 = ph2 + 2.0*PI*F0_IN;
          din_i = $rtoi(amp * $cos(ph2));
          din_q = $rtoi(amp * $sin(ph2));
        end
        if (o_vld) begin
          w = 2.0*PI*F0_OUT*k;
          cr_re = cr_re + o_i*$cos(w);
          cr_im = cr_im + o_i*$sin(w);
          w = 2.0*PI*FIMG*k;
          im_re = im_re + o_i*$cos(w);
          im_im = im_im + o_i*$sin(w);
          k = k + 1;
        end
      end
      mag_c = $sqrt(cr_re*cr_re + cr_im*cr_im);
      mag_i = $sqrt(im_re*im_re + im_im*im_im);
      img_dbc = 20.0 * ($ln(mag_i/mag_c) / $ln(10.0));
      if (img_dbc > -40.0) begin
        errs = errs + 1;
        $display("  FAIL image rejection: %.1f dBc (limit -40) -- halfband polyphase misaligned", img_dbc);
      end else
        $display("  ok  image rejection: %.1f dBc", img_dbc);
    end
  endtask

  initial begin
    repeat (4) @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    test_dc(16'sd5000);
    test_dc(-16'sd3000);
    test_sine_bound;
    test_image_rejection;

    if (errs == 0) $display("tb_tx_halfband_interp2: PASS");
    else           $display("tb_tx_halfband_interp2: FAIL errs=%0d", errs);
    $finish;
  end
endmodule
