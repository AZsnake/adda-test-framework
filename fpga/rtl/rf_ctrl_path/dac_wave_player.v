// AD9117 waveform player (DDR TX path, IFIRST=1, IRISING=1).
//
// 256K-sample (1 MB) URAM-backed IQ playback engine.  Loaded by the UART
// FSM via i_wr_* port (32-bit IQ pair per write).  When i_play_en=1, the
// player reads one IQ pair every 2 sys_clk cycles and emits PARALLEL 16-bit
// I/Q at 61.44 MSa/s/ch.  Downstream tx_iq_dsp does 2x halfband interp
// (-> 122.88/ch) and 16->14 reduction; tx_ddr_out DDR-interleaves I/Q.
//
// URAM word layout:   [31:16] = I (s16),  [15:0] = Q (s16)
//
// Write port restriction: i_wr_en must only pulse while i_play_en=0
// (UART parser enforces this).  No read/write arbitration is implemented;
// concurrent r/w produces unspecified data.
module dac_wave_player (
  input  wire        i_clk,
  input  wire        i_rst_n,

  input  wire        i_play_en,
  input  wire [17:0] i_loop_len_minus1,
  input  wire        i_swap_iq,
  input  wire        i_neg_q,

  input  wire        i_wr_en,
  input  wire [17:0] i_wr_addr,
  input  wire [31:0] i_wr_data,

  output reg signed [15:0] o_iq_i16,
  output reg signed [15:0] o_iq_q16,
  output reg               o_iq_vld
);

  reg [17:0] fetch_addr;
  reg        fetch_phase;   // toggles every cycle; sample on rising edge
  reg        fetch_run;

  (* ram_style = "ultra" *) reg [31:0] mem [0:262143];
  reg [31:0] mem_dout_p1;
  reg [31:0] mem_dout;

  always @(posedge i_clk) begin
    if (i_wr_en) mem[i_wr_addr] <= i_wr_data;
  end
  always @(posedge i_clk) begin
    mem_dout_p1 <= mem[fetch_addr];
    mem_dout    <= mem_dout_p1;
  end

  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      fetch_addr  <= 18'd0;
      fetch_phase <= 1'b0;
      fetch_run   <= 1'b0;
    end else if (!i_play_en) begin
      fetch_addr  <= 18'd0;
      fetch_phase <= 1'b0;
      fetch_run   <= 1'b0;
    end else begin
      fetch_run   <= 1'b1;
      fetch_phase <= ~fetch_phase;
      if (fetch_run && fetch_phase) begin
        fetch_addr <= (fetch_addr == i_loop_len_minus1) ? 18'd0
                                                       : fetch_addr + 1'b1;
      end
    end
  end

  reg phase_d1, run_d1;
  reg phase_d2, run_d2;
  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      phase_d1 <= 1'b0; run_d1 <= 1'b0;
      phase_d2 <= 1'b0; run_d2 <= 1'b0;
    end else begin
      phase_d1 <= fetch_phase;
      run_d1   <= fetch_run;
      phase_d2 <= phase_d1;
      run_d2   <= run_d1;
    end
  end

  wire signed [15:0] samp_i_raw = mem_dout[31:16];
  wire signed [15:0] samp_q_raw = mem_dout[15:0];
  wire signed [15:0] samp_q_adj = i_neg_q ? -samp_q_raw : samp_q_raw;

  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      o_iq_i16 <= 16'sd0; o_iq_q16 <= 16'sd0; o_iq_vld <= 1'b0;
    end else if (!run_d2) begin
      o_iq_i16 <= 16'sd0; o_iq_q16 <= 16'sd0; o_iq_vld <= 1'b0;
    end else begin
      o_iq_vld <= phase_d2;
      if (phase_d2) begin
        o_iq_i16 <= i_swap_iq ? samp_q_adj : samp_i_raw;
        o_iq_q16 <= i_swap_iq ? samp_i_raw : samp_q_adj;
      end
    end
  end

endmodule
