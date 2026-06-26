`timescale 1ns / 1ps

module tb_adc_iq_rx_chain;
  reg adc_clk = 0;
  reg sys_clk = 0;
  reg rst_n = 0;
  always #8  adc_clk = ~adc_clk;   // 62.5 MHz
  always #26 sys_clk = ~sys_clk;   // ~19.2 MHz

  reg [13:0] adc_i = 14'h0000;
  reg [13:0] adc_q = 14'h0000;
  wire signed [13:0] o_i;
  wire signed [13:0] o_q;
  wire o_vld;
  wire fifo_afull, fifo_aempty;

  adc_iq_rx_chain dut (
    .i_adc_clk       (adc_clk),
    .i_sys_clk       (sys_clk),
    .i_rst_n         (rst_n),
    .i_adc_i         (adc_i),
    .i_adc_q         (adc_q),
    .i_dec_ratio     (2'd2),
    .i_nco_freq_word (16'd0),
    .i_iq_bypass     (1'b1),
    .i_iq_mult_op1   (16'sd16384),
    .i_iq_mult_op2   (16'sd0),
    .i_iq_offset_i   (14'sd0),
    .i_iq_offset_q   (14'sd0),
    .i_fir_bypass    (1'b1),
    .i_fir_sel       (2'd0),
    .o_iq_i          (o_i),
    .o_iq_q          (o_q),
    .o_iq_vld        (o_vld),
    .o_fifo_almst_full (fifo_afull),
    .o_fifo_almst_empty(fifo_aempty)
  );

  integer k;
  integer got = 0;
  initial begin
    repeat (10) @(posedge adc_clk);
    rst_n = 1;
    for (k = 0; k < 300; k = k + 1) begin
      @(posedge adc_clk);
      adc_i <= (k[9:0] & 14'h01ff);
      adc_q <= -$signed({4'b0, k[9:0] & 10'h1ff});
    end
    repeat (500) @(posedge sys_clk);
    if (got > 10) $display("tb_adc_iq_rx_chain: PASS");
    else          $display("tb_adc_iq_rx_chain: FAIL got=%0d", got);
    $finish;
  end

  always @(posedge sys_clk) begin
    if (o_vld) got <= got + 1;
  end
endmodule
