`timescale 1ns / 1ps

// ddc_complex_mixer_v2
// 14-bit signed complex mixer with valid gating.
// When i_data_vld=1:
//   I' = I*cos - Q*sin
//   Q' = I*sin + Q*cos
module ddc_complex_mixer_v2 (
  input  wire                i_clk          ,
  input  wire                i_rst_n        ,
  input  wire                i_data_vld     ,
  input  wire signed [13:0]  i_data_i       ,
  input  wire signed [13:0]  i_data_q       ,
  input  wire [15:0]         i_nco_freq_word,
  output reg  signed [13:0]  o_data_i       ,
  output reg  signed [13:0]  o_data_q       ,
  output reg                 o_data_vld
);

  function signed [15:0] sin_from_phase;
    input [7:0] ph;
    begin
      case (ph[7:3])
        5'd0:  sin_from_phase = 16'sd0;
        5'd1:  sin_from_phase = 16'sd1598;
        5'd2:  sin_from_phase = 16'sd3135;
        5'd3:  sin_from_phase = 16'sd4551;
        5'd4:  sin_from_phase = 16'sd5792;
        5'd5:  sin_from_phase = 16'sd6811;
        5'd6:  sin_from_phase = 16'sd7567;
        5'd7:  sin_from_phase = 16'sd8034;
        5'd8:  sin_from_phase = 16'sd8191;
        5'd9:  sin_from_phase = 16'sd8034;
        5'd10: sin_from_phase = 16'sd7567;
        5'd11: sin_from_phase = 16'sd6811;
        5'd12: sin_from_phase = 16'sd5792;
        5'd13: sin_from_phase = 16'sd4551;
        5'd14: sin_from_phase = 16'sd3135;
        5'd15: sin_from_phase = 16'sd1598;
        5'd16: sin_from_phase = 16'sd0;
        5'd17: sin_from_phase = -16'sd1598;
        5'd18: sin_from_phase = -16'sd3135;
        5'd19: sin_from_phase = -16'sd4551;
        5'd20: sin_from_phase = -16'sd5792;
        5'd21: sin_from_phase = -16'sd6811;
        5'd22: sin_from_phase = -16'sd7567;
        5'd23: sin_from_phase = -16'sd8034;
        5'd24: sin_from_phase = -16'sd8191;
        5'd25: sin_from_phase = -16'sd8034;
        5'd26: sin_from_phase = -16'sd7567;
        5'd27: sin_from_phase = -16'sd6811;
        5'd28: sin_from_phase = -16'sd5792;
        5'd29: sin_from_phase = -16'sd4551;
        5'd30: sin_from_phase = -16'sd3135;
        5'd31: sin_from_phase = -16'sd1598;
        default: sin_from_phase = 16'sd0;
      endcase
    end
  endfunction

  reg  [23:0] phase_acc;
  wire [23:0] phase_step = {i_nco_freq_word, 8'h00};
  wire [23:0] phase_next = phase_acc + phase_step;
  wire [7:0]  ph_i_next  = phase_next[23:16];
  wire [7:0]  ph_q_next  = ph_i_next + 8'd64;

  wire signed [15:0] sin_val = sin_from_phase(ph_i_next);
  wire signed [15:0] cos_val = sin_from_phase(ph_q_next);

  wire signed [29:0] ii = i_data_i * cos_val;
  wire signed [29:0] qq = i_data_q * sin_val;
  wire signed [29:0] iq = i_data_i * sin_val;
  wire signed [29:0] qi = i_data_q * cos_val;
  wire signed [30:0] iout_full = $signed(ii) - $signed(qq);
  wire signed [30:0] qout_full = $signed(iq) + $signed(qi);
  wire signed [17:0] iout_sc = iout_full[30:13];
  wire signed [17:0] qout_sc = qout_full[30:13];

  function signed [13:0] sat14;
    input signed [17:0] x;
    begin
      if (x > 18'sd8191)       sat14 = 14'sh1FFF;
      else if (x < -18'sd8192) sat14 = -14'sh2000;
      else                      sat14 = x[13:0];
    end
  endfunction

  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      phase_acc   <= 24'd0;
      o_data_i    <= 14'sd0;
      o_data_q    <= 14'sd0;
      o_data_vld  <= 1'b0;
    end else begin
      o_data_vld <= i_data_vld;
      if (i_data_vld) begin
        phase_acc <= phase_next;
        o_data_i  <= sat14(iout_sc);
        o_data_q  <= sat14(qout_sc);
      end
    end
  end

endmodule
