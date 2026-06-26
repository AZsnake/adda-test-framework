`timescale 1ns / 1ps

// Smoke test for rf_iq_balance14 (o_data_vld <= i_data_vld @ posedge).
//
// Stimulus must change i_vld on negedge so the next posedge sees stable vld=1.
// (#delay-only drive can land on the same timestep as posedge and be missed.)
//
// XSim: top = tb_iq_balance_smoke; add rf_iq_balance14.v to Simulation Sources.
// After any $finish: restart ; run 500ns
module tb_iq_balance_smoke;
  reg clk = 0;
  reg rst_n = 0;
  localparam integer CLK_HALF = 5;  // 10 ns period

  initial forever #(CLK_HALF) clk = ~clk;

  reg                i_vld;
  reg signed [13:0]  i_i;
  reg signed [13:0]  i_q;
  wire signed [13:0] o_i;
  wire signed [13:0] o_q;
  wire               o_vld;

  rf_iq_balance14 dut (
    .i_clk      (clk),
    .i_rst_n    (rst_n),
    .i_data_vld (i_vld),
    .i_data_i   (i_i),
    .i_data_q   (i_q),
    .i_bypass   (1'b0),
    .i_mult_op1 (16'sd16384),
    .i_mult_op2 (16'sd0),
    .i_offset_i (14'sd0),
    .i_offset_q (14'sd0),
    .o_data_i   (o_i),
    .o_data_q   (o_q),
    .o_data_vld (o_vld)
  );

  integer nerr = 0;

  initial begin
    #0 $display("tb_iq_balance_smoke: start @ %0t", $time);
    i_vld = 1'b0;
    i_i   = 14'sd0;
    i_q   = 14'sd0;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    @(negedge clk);
    i_vld = 1'b1;
    i_i   = 14'sd1234;
    i_q   = -14'sd567;
    @(posedge clk);
    #1;

    if (o_vld != 1'b1) begin
      $display("tb_iq_balance_smoke: no valid output (o_vld=%b @ %0t)", o_vld, $time);
      nerr = nerr + 1;
    end else if (o_i !== 14'sd1234 || o_q !== -14'sd567) begin
      $display("tb_iq_balance_smoke: value mismatch I=%0d Q=%0d (expect 1234 / -567)",
               o_i, o_q);
      nerr = nerr + 1;
    end

    i_vld = 1'b0;

    if (nerr == 0) $display("tb_iq_balance_smoke: PASS @ %0t", $time);
    else           $display("tb_iq_balance_smoke: FAIL errs=%0d @ %0t", nerr, $time);
    $finish;
  end
endmodule
