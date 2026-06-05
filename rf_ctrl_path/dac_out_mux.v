// DAC output mux + final output register.
//
// Selects between dac_tone_gen (i_sel=0) and dac_wave_player (i_sel=1).
// Pad timing is closed in tx_ddr_out (ODDRE1 per DB bit); see adda_dac_ddr.xdc.
//
// i_sel must be stable when switching sources (not toggled per cycle).
// One-cycle latency through this mux.
module dac_out_mux (
  input  wire        i_clk,
  input  wire        i_rst_n,

  input  wire        i_sel,        // 0 = tone_gen, 1 = wave_player

  input  wire [13:0] i_tone_db,
  input  wire        i_tone_dci,

  input  wire [13:0] i_wave_db,
  input  wire        i_wave_dci,

  output reg  [13:0] o_dac_db,
  output reg         o_dac_dci
);

  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      o_dac_db  <= 14'h0000;
      o_dac_dci <= 1'b0;
    end else begin
      o_dac_db  <= i_sel ? i_wave_db  : i_tone_db;
      o_dac_dci <= i_sel ? i_wave_dci : i_tone_dci;
    end
  end

endmodule
