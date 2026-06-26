`timescale 1ns / 1ps

// 14-bit RX shaping filter — 15-tap symmetric FIR, Q15 coefficients.
//
// Selectable coefficient banks (i_coef_sel), all Hamming-windowed sinc, DC
// gain ~= 1.0 (Q15 sum ~= 32768).  Banks are quasi-static: i_coef_sel is
// expected to change rarely (set once over UART 0x45 bit[6:5]); the selected
// coefficients are registered so the bank-select mux stays off the per-sample
// MAC critical path.
//
//   sel=0  fc ~ Fs/8   (default; legacy bring-up coefficients, unchanged)
//   sel=1  fc ~ Fs/16  (narrower — stronger anti-alias / noise reduction)
//   sel=2  CIC droop comp (3-stage sinc^3 inverse; flattens the preceding
//                       cic_decimator passband droop.  Combined CIC*comp is
//                       flat to ~0.18 dB p-p for F<=0.10 and ~0.40 dB p-p for
//                       F<=0.15 of the output Nyquist, vs the uncompensated
//                       -0.43 / -0.97 dB CIC droop.  15 taps limit further
//                       correction.  Coeffs from tools/scripts/adc/gen_cic_comp_fir.py.
//                       Replaced the former "fc ~ Fs/4 wide" bank.)
//   sel=3  all-pass    (center tap only; flat response, same latency as a
//                       real filter — a "FIR engaged, no shaping" reference
//                       that, unlike i_bypass, still exercises the MAC path)
//
// i_bypass=1 outputs i_data registered by 1 cycle (matches the original
// placeholder so chains using bypass keep their existing latency).
//
// Latency when bypass=0: 1 cycle (single output register; comb mac sum).
// Both I and Q instances run from the same i_data_vld, so the chain's
// `fir_vld_i & fir_vld_q` AND remains in lockstep.
module rf_filter14 (
  input  wire                i_clk      ,
  input  wire                i_rst_n    ,
  input  wire                i_data_vld ,
  input  wire signed [13:0]  i_data     ,
  input  wire                i_bypass   ,
  input  wire [1:0]          i_coef_sel ,  // coefficient bank (0..3)
  output reg  signed [13:0]  o_data     ,
  output reg                 o_data_vld
);

  // ===== Coefficient banks =====
  // h[0..14] symmetric (h[k] = h[14-k]); c0..c6 are mirror-pair taps, c7 is
  // the center tap.  Registered selection keeps the mux out of the MAC path.
  // sel=0 reproduces the original hard-coded coefficients bit-for-bit.
  reg signed [15:0] c0, c1, c2, c3, c4, c5, c6, c7;

  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      // default = sel 0 (fc ~ Fs/8), sum = 32789
      c0 <= -16'sd80;  c1 <= -16'sd207; c2 <= -16'sd354; c3 <=  16'sd0;
      c4 <=  16'sd1500;c5 <=  16'sd4726;c6 <=  16'sd6920;c7 <=  16'sd7779;
    end else begin
      case (i_coef_sel)
        2'd1: begin // fc ~ Fs/16 (narrow), sum = 32769
          c0 <=  16'sd58;  c1 <=  16'sd198; c2 <=  16'sd625; c3 <=  16'sd1461;
          c4 <=  16'sd2641;c5 <=  16'sd3903;c6 <=  16'sd4877;c7 <=  16'sd5243;
        end
        2'd2: begin // CIC droop comp (sinc^3 inverse), sum = 32768
          c0 <=  16'sd70; c1 <= -16'sd136; c2 <= -16'sd254; c3 <=  16'sd1035;
          c4 <= -16'sd416;c5 <= -16'sd3126;c6 <=  16'sd5317; c7 <=  16'sd27788;
        end
        2'd3: begin // all-pass (center tap only), sum = 32767 (-0.0003 dB)
          c0 <=  16'sd0;  c1 <=  16'sd0;   c2 <=  16'sd0;   c3 <=  16'sd0;
          c4 <=  16'sd0;  c5 <=  16'sd0;   c6 <=  16'sd0;   c7 <=  16'sd32767;
        end
        default: begin // sel 0: fc ~ Fs/8, sum = 32789
          c0 <= -16'sd80;  c1 <= -16'sd207; c2 <= -16'sd354; c3 <=  16'sd0;
          c4 <=  16'sd1500;c5 <=  16'sd4726;c6 <=  16'sd6920;c7 <=  16'sd7779;
        end
      endcase
    end
  end

  reg signed [13:0] d0,  d1,  d2,  d3,  d4,  d5,  d6,  d7,
                    d8,  d9,  d10, d11, d12, d13, d14;

  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      d0  <= 14'sd0; d1  <= 14'sd0; d2  <= 14'sd0; d3  <= 14'sd0;
      d4  <= 14'sd0; d5  <= 14'sd0; d6  <= 14'sd0; d7  <= 14'sd0;
      d8  <= 14'sd0; d9  <= 14'sd0; d10 <= 14'sd0; d11 <= 14'sd0;
      d12 <= 14'sd0; d13 <= 14'sd0; d14 <= 14'sd0;
    end else if (i_data_vld) begin
      d14 <= d13; d13 <= d12; d12 <= d11; d11 <= d10;
      d10 <= d9;  d9  <= d8;  d8  <= d7;  d7  <= d6;
      d6  <= d5;  d5  <= d4;  d4  <= d3;  d3  <= d2;
      d2  <= d1;  d1  <= d0;  d0  <= i_data;
    end
  end

  // Exploit symmetry: sum mirror pairs first, halves the multiplier count.
  wire signed [14:0] s0 = $signed({d0[13],  d0})  + $signed({d14[13], d14});
  wire signed [14:0] s1 = $signed({d1[13],  d1})  + $signed({d13[13], d13});
  wire signed [14:0] s2 = $signed({d2[13],  d2})  + $signed({d12[13], d12});
  wire signed [14:0] s3 = $signed({d3[13],  d3})  + $signed({d11[13], d11});
  wire signed [14:0] s4 = $signed({d4[13],  d4})  + $signed({d10[13], d10});
  wire signed [14:0] s5 = $signed({d5[13],  d5})  + $signed({d9[13],  d9});
  wire signed [14:0] s6 = $signed({d6[13],  d6})  + $signed({d8[13],  d8});
  wire signed [13:0] sc = d7;

  wire signed [31:0] p0 = s0 * c0;
  wire signed [31:0] p1 = s1 * c1;
  wire signed [31:0] p2 = s2 * c2;
  wire signed [31:0] p3 = s3 * c3;
  wire signed [31:0] p4 = s4 * c4;
  wire signed [31:0] p5 = s5 * c5;
  wire signed [31:0] p6 = s6 * c6;
  wire signed [31:0] pc = sc * c7;

  wire signed [34:0] acc = $signed({{3{p0[31]}}, p0}) + $signed({{3{p1[31]}}, p1})
                         + $signed({{3{p2[31]}}, p2}) + $signed({{3{p3[31]}}, p3})
                         + $signed({{3{p4[31]}}, p4}) + $signed({{3{p5[31]}}, p5})
                         + $signed({{3{p6[31]}}, p6}) + $signed({{3{pc[31]}}, pc});

  // Round-half-up then arithmetic shift by 15 (Q15 → integer).
  wire signed [34:0] acc_r = acc + 35'sd16384;
  wire signed [19:0] acc_s = acc_r[34:15];

  function signed [13:0] sat14;
    input signed [19:0] x;
    begin
      if (x > 20'sd8191)        sat14 = 14'sh1FFF;
      else if (x < -20'sd8192)  sat14 = -14'sh2000;
      else                       sat14 = x[13:0];
    end
  endfunction

  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      o_data     <= 14'sd0;
      o_data_vld <= 1'b0;
    end else begin
      o_data_vld <= i_data_vld;
      if (i_data_vld) begin
        o_data <= i_bypass ? i_data : sat14(acc_s);
      end
    end
  end
endmodule
