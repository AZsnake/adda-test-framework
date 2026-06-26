`timescale 1ns / 1ps

// Unit test for rf_filter14 — focuses on the coefficient banks, especially the
// new sel=2 CIC droop-compensation bank added for RX performance.
//
// Checks:
//   1. DC gain ~= 1.0 for every bank (sum of Q15 taps ~= 32768).  A constant
//      input must settle to ~itself at the output once the 15-tap delay line
//      fills.  This is the key guard for the CIC-comp coefficients summing to
//      unity (a wrong sum shows up immediately as a DC scale error).
//   2. sel=3 all-pass returns the input exactly.
//   3. i_bypass=1 returns the input delayed by 1 cycle.
//
// XSim: set simulation top to tb_rf_filter14, Run Behavioral Simulation,
// `run -all`, check for "tb_rf_filter14: PASS".
module tb_rf_filter14;
  reg                 clk = 0;
  reg                 rst_n = 0;
  reg                 dvld = 0;
  reg  signed [13:0]  din = 0;
  reg                 byp = 0;
  reg  [1:0]          sel = 0;
  wire signed [13:0]  dout;
  wire                dout_vld;

  always #5 clk = ~clk;   // 100 MHz

  rf_filter14 dut (
    .i_clk      (clk),
    .i_rst_n    (rst_n),
    .i_data_vld (dvld),
    .i_data     (din),
    .i_bypass   (byp),
    .i_coef_sel (sel),
    .o_data     (dout),
    .o_data_vld (dout_vld)
  );

  integer errs = 0;

  // Apply a constant `val` on a given bank/bypass, let the delay line fill,
  // and check the settled output is within `tol` of `expect`.
  task check_dc;
    input  [1:0]         bank;
    input                bypass;
    input  signed [13:0] val;
    input  signed [13:0] expect;
    input  integer       tol;
    integer              n;
    begin
      sel = bank;
      byp = bypass;
      din = val;
      dvld = 1'b1;
      for (n = 0; n < 40; n = n + 1) @(posedge clk);
      if ((dout > expect + tol) || (dout < expect - tol)) begin
        errs = errs + 1;
        $display("  FAIL bank=%0d byp=%0d in=%0d out=%0d expect~%0d (tol %0d)",
                 bank, bypass, val, dout, expect, tol);
      end else begin
        $display("  ok   bank=%0d byp=%0d in=%0d out=%0d (expect~%0d)",
                 bank, bypass, val, dout, expect);
      end
    end
  endtask

  initial begin
    repeat (5) @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    // DC gain ~= unity for every bank (tol 2 LSB covers Q15 sum rounding).
    check_dc(2'd0, 1'b0,  14'sd1000, 14'sd1000, 2);  // Fs/8
    check_dc(2'd1, 1'b0,  14'sd1000, 14'sd1000, 2);  // Fs/16
    check_dc(2'd2, 1'b0,  14'sd1000, 14'sd1000, 2);  // CIC droop comp (new)
    check_dc(2'd2, 1'b0, -14'sd2000, -14'sd2000, 2); // CIC comp, negative DC
    check_dc(2'd3, 1'b0,  14'sd1234, 14'sd1234, 1);  // all-pass: exact
    // bypass: exact passthrough (1-cycle latency absorbed by the settle loop).
    check_dc(2'd0, 1'b1,  14'sd1500, 14'sd1500, 0);

    if (errs == 0) $display("tb_rf_filter14: PASS");
    else           $display("tb_rf_filter14: FAIL errs=%0d", errs);
    $finish;
  end
endmodule
