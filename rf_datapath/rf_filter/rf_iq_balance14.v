`timescale 1ns / 1ps

// Lightweight 14-bit IQ balance block.
// Provides bypass, per-channel DC offset, and Q-path correction:
//   I_out = I + off_I
//   Q_out = OP1 * (Q + off_Q) + OP2 * (I + off_I)
// Coefficients are Q2.14 fixed-point (0x4000 = 1.0).
module rf_iq_balance14 (
  input  wire                i_clk          ,
  input  wire                i_rst_n        ,
  input  wire                i_data_vld     ,
  input  wire signed [13:0]  i_data_i       ,
  input  wire signed [13:0]  i_data_q       ,
  input  wire                i_bypass       ,
  input  wire signed [15:0]  i_mult_op1     ,
  input  wire signed [15:0]  i_mult_op2     ,
  input  wire signed [13:0]  i_offset_i     ,
  input  wire signed [13:0]  i_offset_q     ,
  output reg  signed [13:0]  o_data_i       ,
  output reg  signed [13:0]  o_data_q       ,
  output reg                 o_data_vld
);

  wire signed [14:0] i_off = i_data_i + i_offset_i;
  wire signed [14:0] q_off = i_data_q + i_offset_q;
  // Keep OP1 on Q and OP2 as I->Q cross-coupling. The previous swapped
  // mapping (OP1 on I, OP2 on Q) made the default OP1=1,OP2=0 collapse
  // Q_out ~= I_out, which visually forced I/Q in-phase.
  wire signed [30:0] q_mix = $signed(q_off) * $signed(i_mult_op1) +
                             $signed(i_off) * $signed(i_mult_op2);
  // Q2.14 -> signed integer.
  wire signed [16:0] q_mix_s = q_mix[30:14];

  function signed [13:0] sat14;
    input signed [16:0] x;
    begin
      if (x > 15'sd8191)       sat14 = 14'sh1FFF;
      else if (x < -15'sd8192) sat14 = -14'sh2000;
      else                      sat14 = x[13:0];
    end
  endfunction

  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      o_data_i   <= 14'sd0;
      o_data_q   <= 14'sd0;
      o_data_vld <= 1'b0;
    end else begin
      o_data_vld <= i_data_vld;
      if (i_data_vld) begin
        if (i_bypass) begin
          o_data_i <= i_data_i;
          o_data_q <= i_data_q;
        end else begin
          o_data_i <= sat14(i_off);
          o_data_q <= sat14(q_mix_s);
        end
      end
    end
  end

endmodule
