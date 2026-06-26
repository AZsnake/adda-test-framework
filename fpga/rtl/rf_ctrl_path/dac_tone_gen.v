// DAC waveform generator for AD9117 DDR TX path (IFIRST=1, IRISING=1).
//
// UART programming model:
//   - i_tone_en:     0x40 enable/disable
//   - i_wave_sel:    0x41 (0=sine, 1=square, 2=triangle, 3=ramp, 4=dc_test)
//   - i_freq_word:   0x42 (16-bit frequency tuning word)
//   - i_amp_pct:     0x43 (0..100 %FS)
//
// Frequency relation (post-interp output at 122.88 MSa/s/ch):
//   f_out = i_freq_word * i_clk_Hz / 65536
// Example: at i_clk=122.88 MHz, i_freq_word=85 gives ~159.38 kHz.
//
// Emits parallel signed 16-bit I/Q at 61.44 MSa/s/ch (o_iq_vld every 2 i_clk)
// for tx_iq_dsp 2x halfband interpolation -> 122.88 MSa/s/ch -> tx_ddr_out.
//
// Pipeline (sys_clk @ 122.88 MHz, 5-cycle latency, subsampled output):
//   S0  phase accumulator (every cycle)
//   S1  registered phase / wave_sel (on emit tick)
//   S2  waveform LUT lookup
//   S3  amplitude multiply (16x16 signed)
//   S4  >>16, saturate, signed 16-bit
//   out registered every 2 cycles (61.44 MSa/s/ch)
module dac_tone_gen (
  input  wire        i_clk    ,  // sys_clk @ 122.88 MHz
  input  wire        i_rst_n  ,
  input  wire        i_tone_en,  // UART 0x40 sticky enable
  input  wire [2:0]  i_wave_sel,  // UART 0x41
  input  wire [15:0] i_freq_word, // UART 0x42
  input  wire [7:0]  i_amp_pct,   // UART 0x43 (0..100)

  output reg signed [15:0] o_iq_i16,
  output reg signed [15:0] o_iq_q16,
  output reg               o_iq_vld
);

  // 256-point sine via quarter-wave symmetry.
  function signed [15:0] sine_quarter_lut;
    input [5:0] k;
    begin
      case (k)
        6'd0:  sine_quarter_lut = 16'sd101;
        6'd1:  sine_quarter_lut = 16'sd301;
        6'd2:  sine_quarter_lut = 16'sd502;
        6'd3:  sine_quarter_lut = 16'sd703;
        6'd4:  sine_quarter_lut = 16'sd903;
        6'd5:  sine_quarter_lut = 16'sd1102;
        6'd6:  sine_quarter_lut = 16'sd1301;
        6'd7:  sine_quarter_lut = 16'sd1499;
        6'd8:  sine_quarter_lut = 16'sd1696;
        6'd9:  sine_quarter_lut = 16'sd1893;
        6'd10: sine_quarter_lut = 16'sd2088;
        6'd11: sine_quarter_lut = 16'sd2281;
        6'd12: sine_quarter_lut = 16'sd2474;
        6'd13: sine_quarter_lut = 16'sd2665;
        6'd14: sine_quarter_lut = 16'sd2854;
        6'd15: sine_quarter_lut = 16'sd3041;
        6'd16: sine_quarter_lut = 16'sd3227;
        6'd17: sine_quarter_lut = 16'sd3411;
        6'd18: sine_quarter_lut = 16'sd3593;
        6'd19: sine_quarter_lut = 16'sd3772;
        6'd20: sine_quarter_lut = 16'sd3950;
        6'd21: sine_quarter_lut = 16'sd4124;
        6'd22: sine_quarter_lut = 16'sd4297;
        6'd23: sine_quarter_lut = 16'sd4467;
        6'd24: sine_quarter_lut = 16'sd4634;
        6'd25: sine_quarter_lut = 16'sd4798;
        6'd26: sine_quarter_lut = 16'sd4960;
        6'd27: sine_quarter_lut = 16'sd5118;
        6'd28: sine_quarter_lut = 16'sd5274;
        6'd29: sine_quarter_lut = 16'sd5426;
        6'd30: sine_quarter_lut = 16'sd5575;
        6'd31: sine_quarter_lut = 16'sd5720;
        6'd32: sine_quarter_lut = 16'sd5863;
        6'd33: sine_quarter_lut = 16'sd6001;
        6'd34: sine_quarter_lut = 16'sd6136;
        6'd35: sine_quarter_lut = 16'sd6267;
        6'd36: sine_quarter_lut = 16'sd6395;
        6'd37: sine_quarter_lut = 16'sd6519;
        6'd38: sine_quarter_lut = 16'sd6638;
        6'd39: sine_quarter_lut = 16'sd6754;
        6'd40: sine_quarter_lut = 16'sd6866;
        6'd41: sine_quarter_lut = 16'sd6973;
        6'd42: sine_quarter_lut = 16'sd7077;
        6'd43: sine_quarter_lut = 16'sd7176;
        6'd44: sine_quarter_lut = 16'sd7271;
        6'd45: sine_quarter_lut = 16'sd7361;
        6'd46: sine_quarter_lut = 16'sd7447;
        6'd47: sine_quarter_lut = 16'sd7528;
        6'd48: sine_quarter_lut = 16'sd7605;
        6'd49: sine_quarter_lut = 16'sd7678;
        6'd50: sine_quarter_lut = 16'sd7745;
        6'd51: sine_quarter_lut = 16'sd7809;
        6'd52: sine_quarter_lut = 16'sd7867;
        6'd53: sine_quarter_lut = 16'sd7921;
        6'd54: sine_quarter_lut = 16'sd7969;
        6'd55: sine_quarter_lut = 16'sd8013;
        6'd56: sine_quarter_lut = 16'sd8053;
        6'd57: sine_quarter_lut = 16'sd8087;
        6'd58: sine_quarter_lut = 16'sd8116;
        6'd59: sine_quarter_lut = 16'sd8141;
        6'd60: sine_quarter_lut = 16'sd8161;
        6'd61: sine_quarter_lut = 16'sd8176;
        6'd62: sine_quarter_lut = 16'sd8185;
        6'd63: sine_quarter_lut = 16'sd8190;
        default: sine_quarter_lut = 16'sd0;
      endcase
    end
  endfunction

  function signed [15:0] sine_from_phase;
    input [7:0] ph;
    reg   [5:0] idx;
    reg  signed [15:0] mag;
    begin
      idx = ph[6] ? ~ph[5:0] : ph[5:0];
      mag = sine_quarter_lut(idx);
      sine_from_phase = ph[7] ? -mag : mag;
    end
  endfunction

  function signed [15:0] tri_from_phase;
    input [7:0] ph;
    reg   [7:0] ramp;
    begin
      ramp = ph[7] ? ~{ph[6:0], 1'b0} : {ph[6:0], 1'b0};
      tri_from_phase = ($signed({1'b0, ramp}) <<< 6) - 16'sd8160;
    end
  endfunction

  function signed [15:0] wave_from_phase;
    input [2:0] sel;
    input [7:0] ph;
    begin
      case (sel)
        3'd1: wave_from_phase = ph[7] ? -16'sd8191 : 16'sd8191;
        3'd2: wave_from_phase = tri_from_phase(ph);
        3'd3: wave_from_phase = $signed({ph, ph});  // sawtooth ramp: 8-bit phase replicated to 16-bit
        default: wave_from_phase = sine_from_phase(ph);
      endcase
    end
  endfunction

  // ===== UART control sync (quasi-static, 2-FF CDC) =====
  reg        tone_en_meta, tone_en_sync;
  reg [2:0]  wave_sel_meta, wave_sel_sync;
  reg [15:0] freq_word_meta, freq_word_sync;
  reg [7:0]  amp_pct_meta, amp_pct_sync;

  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      tone_en_meta   <= 1'b0; tone_en_sync   <= 1'b0;
      wave_sel_meta  <= 3'd0; wave_sel_sync  <= 3'd0;
      freq_word_meta <= 16'd0; freq_word_sync <= 16'd0;
      amp_pct_meta   <= 8'd0; amp_pct_sync   <= 8'd0;
    end else begin
      tone_en_meta   <= i_tone_en;     tone_en_sync   <= tone_en_meta;
      wave_sel_meta  <= i_wave_sel;    wave_sel_sync  <= wave_sel_meta;
      freq_word_meta <= i_freq_word;   freq_word_sync <= freq_word_meta;
      amp_pct_meta   <= i_amp_pct;     amp_pct_sync   <= amp_pct_meta;
    end
  end

  wire [7:0]  amp_clamped = (amp_pct_sync > 8'd100) ? 8'd100 : amp_pct_sync;
  reg  [15:0] amp_q16;
  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) amp_q16 <= 16'd0;
    else          amp_q16 <= amp_clamped * 16'd655;
  end

  // ===== Stage 0: phase accumulator (every cycle) =====
  reg [23:0] phase_acc;
  wire [23:0] phase_step = {freq_word_sync, 8'h00};
  wire [23:0] phase_next = phase_acc + phase_step;

  reg [7:0]  ph_i_s1, ph_q_s1;
  reg [2:0]  wsel_s1;
  reg        run_s1;

  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      phase_acc <= 24'd0;
      ph_i_s1 <= 8'd0; ph_q_s1 <= 8'd0;
      wsel_s1 <= 3'd0; run_s1 <= 1'b0;
    end else if (!tone_en_sync) begin
      phase_acc <= 24'd0;
      ph_i_s1 <= 8'd0; ph_q_s1 <= 8'd0;
      wsel_s1 <= 3'd0; run_s1 <= 1'b0;
    end else begin
      phase_acc <= phase_next;
      ph_i_s1   <= phase_next[23:16];
      ph_q_s1   <= phase_next[23:16] + 8'd64;
      wsel_s1   <= wave_sel_sync;
      run_s1    <= 1'b1;
    end
  end

  // ===== Stage 2: waveform LUT =====
  reg signed [15:0] wave_i_s2, wave_q_s2;
  reg [15:0] amp_q16_s2;
  reg        run_s2;
  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      wave_i_s2 <= 16'sd0; wave_q_s2 <= 16'sd0;
      amp_q16_s2 <= 16'd0; run_s2 <= 1'b0;
    end else begin
      wave_i_s2  <= wave_from_phase(wsel_s1, ph_i_s1);
      wave_q_s2  <= wave_from_phase(wsel_s1, ph_q_s1);
      amp_q16_s2 <= amp_q16;
      run_s2     <= run_s1;
    end
  end

  // ===== Stage 3: amplitude multiply =====
  reg signed [32:0] prod_i_s3, prod_q_s3;
  reg        run_s3;
  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      prod_i_s3 <= 33'sd0; prod_q_s3 <= 33'sd0;
      run_s3 <= 1'b0;
    end else begin
      prod_i_s3 <= $signed(wave_i_s2) * $signed({1'b0, amp_q16_s2});
      prod_q_s3 <= $signed(wave_q_s2) * $signed({1'b0, amp_q16_s2});
      run_s3    <= run_s2;
    end
  end

  // ===== Stage 4: >>16, saturate to signed 16-bit =====
  wire signed [16:0] samp_i_sig = (prod_i_s3 + 33'sd32768) >>> 16;
  wire signed [16:0] samp_q_sig = (prod_q_s3 + 33'sd32768) >>> 16;

  function signed [15:0] sat_s16;
    input signed [16:0] s;
    begin
      if (s < -17'sd32768)      sat_s16 = 16'sh8000;
      else if (s > 17'sd32767)  sat_s16 = 16'sh7FFF;
      else                      sat_s16 = s[15:0];
    end
  endfunction

  reg signed [15:0] samp_i_s4, samp_q_s4;
  reg        run_s4;
  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      samp_i_s4 <= 16'sd0; samp_q_s4 <= 16'sd0;
      run_s4 <= 1'b0;
    end else begin
      samp_i_s4 <= sat_s16(samp_i_sig);
      samp_q_s4 <= sat_s16(samp_q_sig);
      run_s4    <= run_s3;
    end
  end

  // ===== 61.44 MSa/s/ch parallel output (subsample full-rate pipeline) =====
  // dc_test (wave_sel=4): emit a constant so the pipeline keeps producing vld.
  // NOTE: the authoritative DDR bring-up pin pattern (I=0x3FFF / Q=0x0000) is
  // forced downstream in tx_iq_dsp AFTER reduce14 — this 16-bit value only
  // keeps bb_vld active and is otherwise overridden, so its exact level is moot.
  wire dc_test_mode = (wave_sel_sync == 3'd4);

  reg emit_tick;
  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      emit_tick <= 1'b0;
      o_iq_i16 <= 16'sd0; o_iq_q16 <= 16'sd0; o_iq_vld <= 1'b0;
    end else if (dc_test_mode && tone_en_sync) begin
      emit_tick <= ~emit_tick;
      o_iq_i16 <= 16'sd8191;
      o_iq_q16 <= 16'sd0;
      o_iq_vld <= emit_tick;
    end else if (!run_s4) begin
      emit_tick <= 1'b0;
      o_iq_i16 <= 16'sd0; o_iq_q16 <= 16'sd0; o_iq_vld <= 1'b0;
    end else begin
      emit_tick <= ~emit_tick;
      if (emit_tick) begin
        o_iq_i16 <= samp_i_s4;
        o_iq_q16 <= samp_q_s4;
        o_iq_vld <= 1'b1;
      end else begin
        o_iq_vld <= 1'b0;
      end
    end
  end

endmodule
