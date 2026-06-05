`timescale 1ns / 1ps

// ADC bus layout (AD9640, CMOS parallel mode):
//   FPGA_ADC_DA/DB[13:0]  = 14-bit sample (two's complement)
// AD9640 is a 14-bit ADC; DOR is on a separate pin, NOT embedded in the
// parallel data bus.  ILA on raw FPGA_ADC_DB[13:0] shows a clean 14-bit
// ramp across all bits — confirming all 14 bits are data.
//
// The bus is already two's-complement; keep direct signed values through
// CIC / DDC / IQ-balance / FIR / snapshot BRAM / stream FIFO.
//
// Host-side decoders MUST treat captured samples as 14-bit signed
// two's-complement.
//
// HISTORY: an earlier revision masked to [11:0] under the (wrong)
// assumption that [13:12] were DOR/status.  That truncated the 14-bit
// ramp to ±2048 — visible on the host as a sawtooth pinned to the
// 12-bit signed range with frequency-doubled FFT artefacts.  Do NOT
// reinstate the mask.
module adc_iq_rx_chain (
  input  wire                i_adc_clk            ,
  input  wire                i_sys_clk            ,
  input  wire                i_rst_n              ,
  input  wire [13:0]         i_adc_i              ,
  input  wire [13:0]         i_adc_q              ,
  input  wire [1:0]          i_dec_ratio          ,
  input  wire [15:0]         i_nco_freq_word      ,
  input  wire                i_iq_bypass          ,
  input  wire signed [15:0]  i_iq_mult_op1        ,
  input  wire signed [15:0]  i_iq_mult_op2        ,
  input  wire signed [13:0]  i_iq_offset_i        ,
  input  wire signed [13:0]  i_iq_offset_q        ,
  input  wire                i_fir_bypass         ,
  input  wire [1:0]          i_fir_sel            ,  // FIR coefficient bank (0..3)
  // Sys-clk view (through async FIFO, rate-limited by sys_clk).  Used by
  // adc_iq_stream_drain — UART is the bottleneck so dropping samples here
  // is the documented behaviour.
  output wire signed [13:0]  o_iq_i               ,
  output wire signed [13:0]  o_iq_q               ,
  output wire                o_iq_vld             ,
  output wire                o_fifo_almst_full    ,
  output wire                o_fifo_almst_empty   ,
  // Adc-clk direct tap — every chain output, before the async FIFO.  Used
  // by adc_iq_snapshot so the stored sample rate equals adc_clk / dec_ratio.
  output wire signed [13:0]  o_adc_iq_i           ,
  output wire signed [13:0]  o_adc_iq_q           ,
  output wire                o_adc_iq_vld
);

  // Input pipeline register: captures ADC pad data in adc_clk IOB FFs,
  // breaking the timing path from pad → CIC bypass → DDC multiplier chain
  // (11+ levels, 9 ns net delay without this stage).
  (* IOB = "TRUE" *) reg signed [13:0] adc_i_r;
  (* IOB = "TRUE" *) reg signed [13:0] adc_q_r;
  always @(posedge i_adc_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      adc_i_r <= 14'sd0;
      adc_q_r <= 14'sd0;
    end else begin
      adc_i_r <= $signed(i_adc_i);
      adc_q_r <= $signed(i_adc_q);
    end
  end

  wire signed [13:0] cic_i;
  wire signed [13:0] cic_q;
  wire               cic_vld_i;
  wire               cic_vld_q;
  wire               cic_vld = cic_vld_i & cic_vld_q;

  cic_decimator #(.DIN_WIDTH(14), .DOUT_WIDTH(14)) u_cic_i (
    .clk        (i_adc_clk),
    .rst_n      (i_rst_n),
    .i_dec_ratio(i_dec_ratio),
    .i_data     (adc_i_r),
    .i_data_vld (1'b1),
    .o_data     (cic_i),
    .o_data_vld (cic_vld_i)
  );

  cic_decimator #(.DIN_WIDTH(14), .DOUT_WIDTH(14)) u_cic_q (
    .clk        (i_adc_clk),
    .rst_n      (i_rst_n),
    .i_dec_ratio(i_dec_ratio),
    .i_data     (adc_q_r),
    .i_data_vld (1'b1),
    .o_data     (cic_q),
    .o_data_vld (cic_vld_q)
  );

  wire signed [13:0] ddc_i;
  wire signed [13:0] ddc_q;
  wire               ddc_vld;
  ddc_complex_mixer_v2 u_ddc (
    .i_clk          (i_adc_clk),
    .i_rst_n        (i_rst_n),
    .i_data_vld     (cic_vld),
    .i_data_i       (cic_i),
    .i_data_q       (cic_q),
    .i_nco_freq_word(i_nco_freq_word),
    .o_data_i       (ddc_i),
    .o_data_q       (ddc_q),
    .o_data_vld     (ddc_vld)
  );

  wire signed [13:0] bal_i;
  wire signed [13:0] bal_q;
  wire               bal_vld;
  rf_iq_balance14 u_bal (
    .i_clk      (i_adc_clk),
    .i_rst_n    (i_rst_n),
    .i_data_vld (ddc_vld),
    .i_data_i   (ddc_i),
    .i_data_q   (ddc_q),
    .i_bypass   (i_iq_bypass),
    .i_mult_op1 (i_iq_mult_op1),
    .i_mult_op2 (i_iq_mult_op2),
    .i_offset_i (i_iq_offset_i),
    .i_offset_q (i_iq_offset_q),
    .o_data_i   (bal_i),
    .o_data_q   (bal_q),
    .o_data_vld (bal_vld)
  );

  wire signed [13:0] fir_i;
  wire signed [13:0] fir_q;
  wire               fir_vld_i;
  wire               fir_vld_q;
  wire               fir_vld = fir_vld_i & fir_vld_q;

  rf_filter14 u_fir_i (
    .i_clk      (i_adc_clk),
    .i_rst_n    (i_rst_n),
    .i_data_vld (bal_vld),
    .i_data     (bal_i),
    .i_bypass   (i_fir_bypass),
    .i_coef_sel (i_fir_sel),
    .o_data     (fir_i),
    .o_data_vld (fir_vld_i)
  );

  rf_filter14 u_fir_q (
    .i_clk      (i_adc_clk),
    .i_rst_n    (i_rst_n),
    .i_data_vld (bal_vld),
    .i_data     (bal_q),
    .i_bypass   (i_fir_bypass),
    .i_coef_sel (i_fir_sel),
    .o_data     (fir_q),
    .o_data_vld (fir_vld_q)
  );

  wire [31:0] fifo_wdata = {2'b00, fir_q[13:0], 2'b00, fir_i[13:0]};
  wire [31:0] fifo_rdata;
  wire        fifo_empty;
  wire        fifo_rvld;
  wire        fifo_full;

  reg fifo_rd_en;
  always @(posedge i_sys_clk or negedge i_rst_n) begin
    if (!i_rst_n) fifo_rd_en <= 1'b0;
    else          fifo_rd_en <= ~fifo_empty;
  end

  rf_async_fifo #(.DATA_WIDTH(16)) u_fifo (
    .i_r_clk         (i_sys_clk),
    .i_r_rstn        (i_rst_n),
    .i_w_clk         (i_adc_clk),
    .i_w_rstn        (i_rst_n),
    .soft_reset_rclk (1'b0),
    .soft_reset_wclk (1'b0),
    .i_r_en          (fifo_rd_en),
    .i_w_en          (fir_vld),
    .i_wdata         (fifo_wdata),
    .o_rdata         (fifo_rdata),
    .o_rdata_valid   (fifo_rvld),
    .o_r_empty       (fifo_empty),
    .o_w_full        (fifo_full),
    .o_r_almst_empty (o_fifo_almst_empty),
    .o_w_almst_full  (o_fifo_almst_full),
    .o_r_fifo_num    ()
  );

  assign o_iq_i   = fifo_rdata[13:0];
  assign o_iq_q   = fifo_rdata[29:16];
  assign o_iq_vld = fifo_rvld;

  // adc_clk-domain direct tap (pre-FIFO, full rate)
  assign o_adc_iq_i   = fir_i;
  assign o_adc_iq_q   = fir_q;
  assign o_adc_iq_vld = fir_vld;

endmodule
