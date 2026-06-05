`timescale 1ns / 1ps

// TX DSP spine: parallel baseband I/Q -> 2x halfband interpolation -> 14-bit DAC.
//
// All sample sources (dac_tone_gen / dac_wave_player) emit parallel signed
// 16-bit I/Q at 61.44 MSa/s/ch; this module upsamples to 122.88 MSa/s/ch
// for tx_ddr_out (ODDRE1 DDR interleave @ 245.76 MSa/s on FPGA_DAC_DB).
//
//   i_i/i_q (s14-ranged in s16 container @ 61.44/ch, i_in_vld every 2 i_clk)
//     -> tx_halfband_interp2  (2x -> s16 @ 122.88/ch)
//     -> 16->14 narrow: drop the 2 redundant top bits + saturate (NO /4)
//   -> o_i/o_q (s14 @ 122.88/ch, o_vld every i_clk)
//
// Amplitude convention (unified across ALL DAC sources): baseband samples are
// 14-bit signed (+-8191) carried in a 16-bit container.  dac_tone_gen emits
// s14; host wave files are s14; the wave player passes them through verbatim.
// reduce14 therefore maps straight through (1:1) so the DAC reaches full scale.
// An earlier (s+2)>>>2 here divided by 4, leaving the DAC 12 dB below FS.
module tx_iq_dsp (
  input  wire        i_clk,
  input  wire        i_rst_n,
  input  wire        i_in_vld,
  input  wire        i_hb_bypass,  // 1 = skip halfband, sample-repeat 2x upsample
  input  wire        i_dc_test,    // 1 = force DDR bring-up pattern at the 14-bit pins
  input  wire signed [15:0] i_i,
  input  wire signed [15:0] i_q,

  output wire        o_vld,
  output reg  signed [13:0] o_i,
  output reg  signed [13:0] o_q
);

  // ===== Halfband 2x interpolation path =====
  wire               hb_vld;
  wire signed [15:0] hb_i, hb_q;
  tx_halfband_interp2 u_interp (
    .i_clk    (i_clk),
    .i_rst_n  (i_rst_n),
    .i_in_vld (i_in_vld),
    .i_i      (i_i),
    .i_q      (i_q),
    .o_vld    (hb_vld),
    .o_i      (hb_i),
    .o_q      (hb_q)
  );

  // ===== Bypass path: sample-repeat 2x upsample (zero-order hold) =====
  reg signed [15:0] bp_i_hold, bp_q_hold;
  reg               bp_primed;
  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      bp_i_hold <= 16'sd0; bp_q_hold <= 16'sd0;
      bp_primed <= 1'b0;
    end else if (i_in_vld) begin
      bp_i_hold <= i_i;
      bp_q_hold <= i_q;
      bp_primed <= 1'b1;
    end
  end

  wire signed [15:0] mux_i = i_hb_bypass ? bp_i_hold : hb_i;
  wire signed [15:0] mux_q = i_hb_bypass ? bp_q_hold : hb_q;
  wire               mux_vld = i_hb_bypass ? bp_primed : hb_vld;

  // 16->14 narrow with saturation. Input is already 14-bit-ranged (+-8191);
  // only halfband passband/Gibbs overshoot can exceed FS, and that is clamped
  // here. No down-shift: do NOT reintroduce /4.
  function signed [13:0] reduce14;
    input signed [15:0] s;
    begin
      if      (s >  16'sd8191) reduce14 = 14'sh1FFF;
      else if (s < -16'sd8192) reduce14 = 14'sh2000;
      else                      reduce14 = s[13:0];
    end
  endfunction

  reg vld_r;
  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      o_i <= 14'sd0; o_q <= 14'sd0; vld_r <= 1'b0;
    end else if (i_dc_test) begin
      // DDR bring-up test pattern, injected POST-reduce14 so the physical
      // FPGA_DAC_DB pins are exactly: I = all ones, Q = all zeros. (reduce14
      // can never emit 0x3FFF: its positive saturate is 0x1FFF, and 0x3FFF is
      // -1 in 14-bit two's-complement.) Lets you scope any DB bit vs DCLKIO to
      // verify IFIRST/IRISING interleave and the data eye.
      vld_r <= 1'b1;
      o_i   <= 14'h3FFF;   // 14'b11_1111_1111_1111
      o_q   <= 14'h0000;
    end else begin
      vld_r <= mux_vld;
      o_i   <= reduce14(mux_i);
      o_q   <= reduce14(mux_q);
    end
  end

  assign o_vld = vld_r;

endmodule
