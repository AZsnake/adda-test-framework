`timescale 1ns / 1ps

// 2x polyphase halfband interpolator for the AD9117 TX path.
//
// Upsamples baseband I/Q from 61.44 MSa/s/ch to 122.88 MSa/s/ch so the DDR DAC
// bus can run at 245.76 MSa/s interleaved (< AD9117 250 MSPS / 125 MHz ceiling).
// This pushes the spectral image from ~Fs1-f out to ~2*Fs1-f, relaxing the
// analog reconstruction filter and improving SFDR/image rejection.  The AD9117
// has NO internal interpolation, so this MUST be done in the FPGA.
//
// 19-tap Type-I halfband (Kaiser beta=7), prototype Q15 coeffs (center 0.5).
// Halfband => the even polyphase branch is a pure delay; the odd branch is a
// 5-multiply symmetric FIR.  6 dB interpolation gain is restored with >>14.
// Verified image rejection (signal at f0 of the input Nyquist):
//   f0<=0.10 -> -81 dBc, f0<=0.30 -> -40 dBc, f0<=0.40 -> -16 dBc.
// Coeffs from tools/scripts/dac/gen_halfband_interp.py.
//
// Rate contract (all on i_clk = sys_clk @ 122.88 MHz):
//   i_in_vld pulses 1 cycle every 2 (marks a new 61.44 MSa/s/ch input sample).
//   o_vld is high every cycle once primed; o_i/o_q update at 122.88 MSa/s/ch.
//   Each input sample yields two outputs: the delay-branch sample (on the
//   i_in_vld cycle) and the FIR-interpolated sample (on the next cycle).
//
module tx_halfband_interp2 (
  input  wire        i_clk,
  input  wire        i_rst_n,
  input  wire        i_in_vld,    // new input sample strobe (61.44 MSa/s/ch)
  input  wire signed [15:0] i_i,
  input  wire signed [15:0] i_q,

  output reg         o_vld,
  output reg  signed [15:0] o_i,
  output reg  signed [15:0] o_q
);

  // Prototype Q15 halfband odd-branch pair coeffs (nearest->farthest).
  // gen_halfband_interp.py: CP0 multiplies the innermost input pair.
  localparam signed [15:0] CP0 =  16'sd10023;  // trimmed so sum(CP)=8192 (unity DC)
  localparam signed [15:0] CP1 = -16'sd2403;
  localparam signed [15:0] CP2 =  16'sd706;
  localparam signed [15:0] CP3 = -16'sd141;
  localparam signed [15:0] CP4 =  16'sd7;

  // ===== Input delay lines (10 deep), advanced on i_in_vld =====
  reg signed [15:0] xi0,xi1,xi2,xi3,xi4,xi5,xi6,xi7,xi8,xi9;
  reg signed [15:0] xq0,xq1,xq2,xq3,xq4,xq5,xq6,xq7,xq8,xq9;

  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      xi0<=0;xi1<=0;xi2<=0;xi3<=0;xi4<=0;xi5<=0;xi6<=0;xi7<=0;xi8<=0;xi9<=0;
      xq0<=0;xq1<=0;xq2<=0;xq3<=0;xq4<=0;xq5<=0;xq6<=0;xq7<=0;xq8<=0;xq9<=0;
    end else if (i_in_vld) begin
      xi9<=xi8;xi8<=xi7;xi7<=xi6;xi6<=xi5;xi5<=xi4;
      xi4<=xi3;xi3<=xi2;xi2<=xi1;xi1<=xi0;xi0<=i_i;
      xq9<=xq8;xq8<=xq7;xq7<=xq6;xq6<=xq5;xq5<=xq4;
      xq4<=xq3;xq3<=xq2;xq2<=xq1;xq1<=xq0;xq0<=i_q;
    end
  end

  // ===== Symmetric pair sums (innermost pair = xr4+xr5) =====
  wire signed [16:0] pi0 = $signed({xi4[15],xi4}) + $signed({xi5[15],xi5});
  wire signed [16:0] pi1 = $signed({xi3[15],xi3}) + $signed({xi6[15],xi6});
  wire signed [16:0] pi2 = $signed({xi2[15],xi2}) + $signed({xi7[15],xi7});
  wire signed [16:0] pi3 = $signed({xi1[15],xi1}) + $signed({xi8[15],xi8});
  wire signed [16:0] pi4 = $signed({xi0[15],xi0}) + $signed({xi9[15],xi9});
  wire signed [16:0] pq0 = $signed({xq4[15],xq4}) + $signed({xq5[15],xq5});
  wire signed [16:0] pq1 = $signed({xq3[15],xq3}) + $signed({xq6[15],xq6});
  wire signed [16:0] pq2 = $signed({xq2[15],xq2}) + $signed({xq7[15],xq7});
  wire signed [16:0] pq3 = $signed({xq1[15],xq1}) + $signed({xq8[15],xq8});
  wire signed [16:0] pq4 = $signed({xq0[15],xq0}) + $signed({xq9[15],xq9});

  // 17x16 products, accumulate (sign-extended to 35 bits).
  wire signed [33:0] acc_i = pi0*CP0 + pi1*CP1 + pi2*CP2 + pi3*CP3 + pi4*CP4;
  wire signed [33:0] acc_q = pq0*CP0 + pq1*CP1 + pq2*CP2 + pq3*CP3 + pq4*CP4;

  // >>14 = (Q15 >>15) then x2 interpolation-gain restore; round-half-up.
  wire signed [33:0] acc_i_r = acc_i + 34'sd8192;
  wire signed [33:0] acc_q_r = acc_q + 34'sd8192;
  wire signed [19:0] fir_i = acc_i_r[33:14];
  wire signed [19:0] fir_q = acc_q_r[33:14];

  function signed [15:0] sat16;
    input signed [19:0] x;
    begin
      if (x >  20'sd32767)      sat16 = 16'sh7FFF;
      else if (x < -20'sd32768) sat16 = 16'sh8000;
      else                       sat16 = x[15:0];
    end
  endfunction

  // Delay-branch output = xr5.  The FIR pair is centered between xr4/xr5 (the
  // x[k-4.5] instant); emitting xr5 (x[k-5]) on the i_in_vld cycle then the FIR
  // sample next gives a monotonic 0.5-sample interleave and keeps the two
  // polyphase branches phase-aligned (xr4 instead collapses image rejection --
  // verified in tools/scripts/dac/gen_halfband_interp.py companion check).
  wire signed [15:0] del_i = xi5;
  wire signed [15:0] del_q = xq5;

  // phase: the i_in_vld cycle emits the delay sample, the next cycle the FIR
  // sample.  Register run-state so o_vld only asserts after the line primes.
  reg primed;
  // FIR result must be latched on the SAME cycle the delay sample is sourced.
  // The delay line advances on i_in_vld; fir_i/fir_q are combinational off that
  // line.  If the FIR is sampled on the *next* (i_in_vld=0) cycle, the line has
  // already shifted, so the FIR sample lands 1.5 input-samples after the delay
  // sample instead of 0.5 -> the Fs1-f0 image is left essentially uncancelled
  // (~-7 dBc measured).  Capturing fir_*_hold here (pre-shift snapshot) restores
  // the 0.5-sample interleave and the full halfband image rejection.
  reg signed [15:0] fir_i_hold, fir_q_hold;
  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      o_vld <= 1'b0; o_i <= 16'sd0; o_q <= 16'sd0;
      primed <= 1'b0;
      fir_i_hold <= 16'sd0; fir_q_hold <= 16'sd0;
    end else begin
      if (i_in_vld) primed <= 1'b1;
      o_vld <= primed;
      if (i_in_vld) begin
        o_i <= del_i;
        o_q <= del_q;
        fir_i_hold <= sat16(fir_i);
        fir_q_hold <= sat16(fir_q);
      end else begin
        o_i <= fir_i_hold;
        o_q <= fir_q_hold;
      end
    end
  end

endmodule
