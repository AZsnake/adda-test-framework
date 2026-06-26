// Linear 6-stage BUFGMUX chain: select one of 7 clk_wiz_1 phase taps for DCLKIO.
// clk_sel[2:0] is the phase index (0=90°, 1=135°, …, 6=360°); 7 falls back to 0.
// Linear cascade satisfies UltraScale+ rule_cascaded_bufg (adjacent BUFGCTRL sites).
// clk_sel is quasi-static (dip switches); no synchronizer needed.
module dac_dclk_phase_mux (
  input  wire        clk_in0,  // 90°
  input  wire        clk_in1,  // 135°
  input  wire        clk_in2,  // 180°
  input  wire        clk_in3,  // 225°
  input  wire        clk_in4,  // 270°
  input  wire        clk_in5,  // 315°
  input  wire        clk_in6,  // 360°
  input  wire [2:0]  clk_sel,
  output wire        clk_out
);

  wire [2:0] eff_sel = (clk_sel == 3'd7) ? 3'd0 : clk_sel;

  wire mux_s0, mux_s1, mux_s2, mux_s3, mux_s4, mux_s5;

  wire sel_ge1 = (eff_sel >= 3'd1);
  wire sel_ge2 = (eff_sel >= 3'd2);
  wire sel_ge3 = (eff_sel >= 3'd3);
  wire sel_ge4 = (eff_sel >= 3'd4);
  wire sel_ge5 = (eff_sel >= 3'd5);
  wire sel_ge6 = (eff_sel >= 3'd6);

  BUFGMUX #(
    .CLK_SEL_TYPE ("SYNC")
  ) u_mux_s0 (
    .O  (mux_s0),
    .I0 (clk_in0),
    .I1 (clk_in1),
    .S  (sel_ge1)
  );

  BUFGMUX #(
    .CLK_SEL_TYPE ("SYNC")
  ) u_mux_s1 (
    .O  (mux_s1),
    .I0 (mux_s0),
    .I1 (clk_in2),
    .S  (sel_ge2)
  );

  BUFGMUX #(
    .CLK_SEL_TYPE ("SYNC")
  ) u_mux_s2 (
    .O  (mux_s2),
    .I0 (mux_s1),
    .I1 (clk_in3),
    .S  (sel_ge3)
  );

  BUFGMUX #(
    .CLK_SEL_TYPE ("SYNC")
  ) u_mux_s3 (
    .O  (mux_s3),
    .I0 (mux_s2),
    .I1 (clk_in4),
    .S  (sel_ge4)
  );

  BUFGMUX #(
    .CLK_SEL_TYPE ("SYNC")
  ) u_mux_s4 (
    .O  (mux_s4),
    .I0 (mux_s3),
    .I1 (clk_in5),
    .S  (sel_ge5)
  );

  BUFGMUX #(
    .CLK_SEL_TYPE ("SYNC")
  ) u_mux_s5 (
    .O  (clk_out),
    .I0 (mux_s4),
    .I1 (clk_in6),
    .S  (sel_ge6)
  );

endmodule
