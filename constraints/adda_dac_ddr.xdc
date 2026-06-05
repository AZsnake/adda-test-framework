# DDR DAC output timing — REQUIRED for every rf_adda_top build (the DAC is
# 2x-interpolated DDR only: 122.88 MSa/s/ch -> 245.76 MSa/s interleaved bus,
# DCLKIO 122.88, I on rising / Q on falling = AD9117 IFIRST=1, IRISING=1).
# Add alongside adda_io.xdc + adda_clocks.xdc.
#
# Board/IP prereqs (see rf_adda_top header + docs/tx_interp2x_bringup.md):
#   - SI5340 OUT3 = 122.88 MHz (AD9117 CLKIN).
#   - clk_wiz_0: clk_out1 @ 0 deg (sys_clk). clk_wiz_1: clk_out1..7 @ 90..360 deg
#     (45 deg steps), fed by sys_clk; dac_dclk_phase_mux selects tap for DCLKIO.
#   - DCLKIO ODDRE1 clock = pad_input_s[2:0] phase select (default 000 -> 90 deg).
#   - AD9117 init: reg 0x02 = 0x34; reg 0x14 Reacquire pulse in ad9117_init.txt.
#
# Delay math (AD9117 Table 2 @ 1.8 V LVCMOS, source-synchronous at pad):
#   I @ DCLKIO rising:  tSU=0.13 ns, tH=1.1 ns
#   Q @ DCLKIO falling: tSU=0.25 ns, tH=1.2 ns
#   set_output_delay -max = tSU + board_skew + margin
#   set_output_delay -min = -tH + board_skew
# Update skew after scope measurement — see docs/dac_ddr_timing_bringup.md.

# ---- Board measurement inputs (ns) -----------------------------------------
# skew_I / skew_Q: data valid center relative to DCLKIO active edge at FPGA pads.
# Use 0.0 until scoped; typical PCB+package skew is often 0.1..0.4 ns.
set DAC_BOARD_SKEW_I_NS 0.0
set DAC_BOARD_SKEW_Q_NS 0.0
set DAC_MARGIN_NS       0.08

set DAC_I_MAX_DELAY [expr {0.13 + $DAC_BOARD_SKEW_I_NS + $DAC_MARGIN_NS}]
set DAC_I_MIN_DELAY [expr {-1.1 + $DAC_BOARD_SKEW_I_NS}]
set DAC_Q_MAX_DELAY [expr {0.25 + $DAC_BOARD_SKEW_Q_NS + $DAC_MARGIN_NS}]
set DAC_Q_MIN_DELAY [expr {-1.2 + $DAC_BOARD_SKEW_Q_NS}]

# ---- Forwarded DCLKIO clock (122.88 MHz, from the DCLKIO ODDRE1) ------------
create_generated_clock -name dac_dclkio \
  -source [get_pins u_tx_ddr_out/u_dco_oddr/C] \
  -divide_by 1 \
  [get_ports FPGA_DAC_DCLKIO]

# ---- DB[13:0] DDR output delay vs forwarded DCLKIO (I rising, Q falling) ----
set_output_delay -clock dac_dclkio -max $DAC_I_MAX_DELAY [get_ports {FPGA_DAC_DB[*]}]
set_output_delay -clock dac_dclkio -min $DAC_I_MIN_DELAY [get_ports {FPGA_DAC_DB[*]}]

set_output_delay -clock dac_dclkio -max $DAC_Q_MAX_DELAY -clock_fall -add_delay [get_ports {FPGA_DAC_DB[*]}]
set_output_delay -clock dac_dclkio -min $DAC_Q_MIN_DELAY -clock_fall -add_delay [get_ports {FPGA_DAC_DB[*]}]

# Do NOT set IOB TRUE on DB/DCLKIO: drivers are ODDRE1 in OLOGIC, not fabric FFs.
# IOB applies to FD*/LUT-FF packing; Place 30-722 fires if forced on ODDRE1 ports.
# Timing is closed via set_output_delay vs dac_dclkio above; ODDRE1 already sits at pad.

# ---- Hold multicycle for source-synchronous DDR inter-clock relationship ------
# DB ODDRE1 (sys_clk @ 0°, clk_wiz_0) and DCLKIO ODDRE1 (dac_dclk_clk from
# clk_wiz_1 phase mux, locked to sys_clk). Default pad_input_s[2:0]=000 -> 90°.
# STA sees the mux-selected phase; bring-up calibration uses dip switches on board.
# Vivado's default hold analysis picks edge pairs where the forwarded
# clock arrives T/4 after data transitions, reporting ~-3 ns hold violations.
# The actual hold margin is T/4 - tH ≈ 0.9 ns (positive). Shift the hold launch
# edge by one source period so Vivado checks the correct relationship.
set_multicycle_path -hold 1 \
  -from [get_clocks clk_out1_clk_wiz_0] \
  -to   [get_clocks dac_dclkio]

# If report_timing shows setup violations on DB, adjust pad_input_s[2:0] / clk_wiz_1
# phase toward the measured eye center — do NOT only loosen max output delay.
