# Clock & I/O timing constraints for rf_adda_top.
#   pad_clk_19m2_1 = 19.2 MHz board oscillator (clk_wiz_0 input; IP creates its own primary clock)
#   sys_clk        = 122.88 MHz on clk_wiz_0/clk_out1 @ 0°   (generated clock, IP-published)
#   dac_dclk_clk   = 122.88 MHz from clk_wiz_1 phase mux (pad_input_s[2:0] -> DCLKIO)
#   clk_wiz_0: single output clk_out1 @ 0°, NO dynamic phase shift.
#   clk_wiz_1: input = sys_clk (No buffer), clk_out1..7 @ 90°/135°/…/360° (45° steps).
#              dac_dclk_phase_mux (linear BUFGMUX chain) selects one tap for DCLKIO.
#              Dynamic phase shift is OFF; use dip switches for bring-up calibration.
#   adc_clk        = 122.88 MHz on FPGA_ADC_DCOA (AD9640 source-sync CMOS output, sourced by SI5340 OUT0)
#   AD9117 CLKIN   = 122.88 MHz from SI5340 OUT3 (off-FPGA; not constrained here)

# ---- UltraScale+ configuration --------------------------------------------
# Check CFGBVS pin on VU13P: if tied to GND use "GND"; if tied to VCCO (2.5/3.3V) use "VCCO".
# CONFIG_VOLTAGE must match the VCCO of the configuration bank (all IOs here are LVCMOS18 → 1.8 V).
set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]

# SPI Flash configuration — SPIx4 quad mode, 63.8 MHz, 32-bit address for >128 Mb flash.
set_property BITSTREAM.CONFIG.CONFIGRATE 63.8 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR YES [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE YES [current_design]

# ====== Primary clocks ======================================================

# sys_clk: clk_wiz_0 IP XDC creates the primary clock on pad_clk_19m2_1 (19.2 MHz)
# and the generated clock on clk_out1 (122.88 MHz). Do NOT redefine here.

# adc_clk: anchor at the input port so Vivado can model the IBUF + BUFG insertion
# delay correctly (TIMING-2 'Invalid primary clock source pin' fires if anchored at
# the BUFG output instead).
create_clock -period 8.138 -name adc_clk [get_ports FPGA_ADC_DCOA]

# adc_clk BUFG routing: the IBUF→BUFG net may need to cross CMT columns if the
# ADC IOB (bank 63) and the BUFG land in different columns.  ANY_CMT_COLUMN on
# the pre-BUFG net relaxes the same-column restriction.
set_property CLOCK_DEDICATED_ROUTE ANY_CMT_COLUMN [get_nets -of_objects [get_pins u_adc_clk_bufg/I]]

# dac_dclk_clk (phase-mux output) only drives 1 ODDRE1 (DCLKIO) in X4Y0.
# The default clock root (X3Y7) is 7 rows away, causing Vivado to report
# Route 35-4475 (incomplete guidance tree) for this ultra-low-fanout clock.
# Moving the root to X4Y0 eliminates the warning (Xilinx AR#71607).
set_property USER_CLOCK_ROOT X4Y0 [get_nets -of_objects [get_pins u_dac_dclk_phase_mux/u_mux_s5/O]]

# Linear BUFGMUX chain: relax dedicated-route check on intermediate cascade nets
# (adc_clk uses the same override). Required if placer still reports rule_cascaded_bufg.
set_property CLOCK_DEDICATED_ROUTE ANY_CMT_COLUMN [get_nets -quiet {
  u_dac_dclk_phase_mux/mux_s0
  u_dac_dclk_phase_mux/mux_s1
  u_dac_dclk_phase_mux/mux_s2
  u_dac_dclk_phase_mux/mux_s3
  u_dac_dclk_phase_mux/mux_s4
}]

# sys_clk (clk_wiz_0 @ 0°) + dac_dclk_clk (clk_wiz_1 phase tap, locked to sys_clk).
# XDC must not use "proc" (unsupported).
set sys_clk_obj      [get_clocks -quiet -of_objects [get_nets -quiet -hierarchical sys_clk]]
set dac_dclk_clk_obj [get_clocks -quiet -of_objects [get_nets -quiet -hierarchical dac_dclk_clk]]

# The 0° fabric clock and the selected DCLKIO phase tap are synchronous
# (clk_wiz_1 is locked to sys_clk); adc_clk is asynchronous.
set_clock_groups -asynchronous \
  -group [list $sys_clk_obj $dac_dclk_clk_obj] \
  -group [get_clocks adc_clk]

# ====== DAC DDR output =======================================================
# The 245.76 MSa/s interleaved DDR DAC bus timing (forwarded DCLKIO clock, DB
# both-edge output delays, IOB packing) lives in constraints/adda_dac_ddr.xdc.
# That file is REQUIRED for every rf_adda_top build (the DAC is DDR-only).

# ====== UART (sys_clk domain, 115200 baud — ~8.7 µs/bit, completely slack) ===
# Bit period ~8.68 µs; the RX samples mid-bit, so any ns-scale FPGA→pin skew
# is irrelevant. Use false_path instead of a tight set_output_delay, and pack
# the driving FF into the IOB via XDC (RTL-side (*IOB*) on uart_tx.tx tripped
# Place-30-73 because the FF is several hierarchy levels above the top port).
set_false_path -to   [get_ports o_uart_tx]
set_false_path -from [get_ports i_uart_rx]
set_property IOB TRUE [get_ports o_uart_tx]

# ====== SPI master pins (sys_clk-divided clocks, ≤ a few MHz) ===============
# SPI sclk is generated from sys_clk by rf_spi_core / clock gen.  Bit rate is
# orders of magnitude below sys_clk; precise IO timing is irrelevant for ADDA
# bring-up.  Mark as false paths to silence the no-delay warnings cleanly.
set_false_path -to [get_ports {pad_si5340_sclk pad_si5340_csb pad_si5340_sda pad_si5340_rstb}]
set_false_path -to [get_ports {pad_adc_sclk pad_adc_csb}]
set_false_path -to [get_ports {pad_dac_sclk pad_dac_csb pad_dac_reset}]
set_false_path -from [get_ports pad_si5340_sdo]
# SDIO pins are bidirectional; tri-state OEN is driven by FSM at SPI rate.
set_false_path -from [get_ports {pad_adc_sdio pad_dac_sdio}]
set_false_path -to   [get_ports {pad_adc_sdio pad_dac_sdio}]

# ====== Async reset + low-rate status =====================================
# pad_adda_rstn is an asynchronous reset (debounced externally); RTL uses it as
# async assert + sync deassert via the design's own reset network.
set_false_path -from [get_ports pad_adda_rstn]

# SI5340 status (LOL/LOSX/INTR) and AD9640 SMI clocks/data are all read into
# slow sync FFs; explicit false paths already covered most, complete the list.
set_false_path -from [get_ports pad_si5340_intrb]
set_false_path -from [get_ports pad_si5340_lolb]
set_false_path -from [get_ports pad_si5340_losxb]
set_false_path -from [get_ports pad_adc_smi_clk]
set_false_path -from [get_ports pad_adc_smi_dfs]
set_false_path -from [get_ports pad_adc_smi_sdo]

# ====== LEDs / debug strip (visual only) =================================
set_false_path -to [get_ports {pad_led_red pad_led_blue}]
set_false_path -to [get_ports {pad_output_d[*]}]

# ====== Dip switches (quasi-static DCLKIO phase select) ==================
set_false_path -from [get_ports {pad_input_s[*]}]

# ====== ADC source-synchronous input (AD9640 CMOS parallel) ===================
# AD9640 drives 14-bit data on DA/DB relative to DCOA (adc_clk). Data is SDR,
# center-aligned with DCOA. AD9640 CMOS output timing (datasheet Table 6):
#   tPD (prop delay from clock to data valid): typ 3.5 ns
#   Data is centered on the DCO rising edge; FPGA samples on DCO rising edge.
#   The data appears at the pad ~0 ns relative to DCO (center-aligned).
# For center-aligned SDR: set_input_delay = (T/2 - margin) for max,
#   -margin for min, so the FPGA samples in the center of the data eye.
# T = 8.138 ns -> T/2 = 4.069 ns; use ±1 ns window around midpoint.
set_input_delay -clock adc_clk -max 1.0 [get_ports {FPGA_ADC_DA[*] FPGA_ADC_DB[*]}]
set_input_delay -clock adc_clk -min -1.0 [get_ports {FPGA_ADC_DA[*] FPGA_ADC_DB[*]}]

# IOB packing for ADC data input registers is handled by the RTL attribute
# (* IOB = "TRUE" *) on adc_i_r / adc_q_r in adc_iq_rx_chain.v.  A port-level
# set_property IOB TRUE here targets the port (wrong object on UltraScale+ —
# should target the cell/register) and triggers Chipscope 16-3 when ILA debug
# probes the post-IOB net.  Removed; the RTL attribute is sufficient.

# ====== CDC: sys_clk → adc_clk quasi-static =================================
# i_n_samples (adc_n) is stable in sys_clk before i_arm; sampled into n_adc on
# arm_rise in adc_clk (after 2-FF arm_sync in adc_iq_snapshot).
# 8.138 ns ≈ 1 adc_clk period @ 122.88 MHz.
set_max_delay -datapath_only -from $sys_clk_obj \
  -to [get_cells {u_adc_iq_snapshot/n_adc_reg[*]}] 8.138

# ---- ILA / debug (Labtools 27-1974) -----------------------------------------
# Manual ILA: add Verilog define FPGA_DEBUG_RF (Tools → Settings → Verilog options),
# create ila_adda_sys + ila_adda_adc in IP Catalog, rebuild, then program the
# .bit and .ltx from the same impl_1 run. Do not mix with an older probes file.
# Do not use MARK_DEBUG on the same nets when FPGA_DEBUG_RF is set (see rf_adda_top).
#
# VU13P is a 3-SLR device: if the adc_clk ILA scatters across SLRs, the placer
# can't build a complete clock guidance tree (Route 35-4475).  Constrain the ILA
# and all adc_clk-domain RX logic to the same SLR as the ADC IOBs (SLR 0, bank 63).
create_pblock pblock_adc_clk
add_cells_to_pblock [get_pblocks pblock_adc_clk] [get_cells -quiet u_ila_adc]
add_cells_to_pblock [get_pblocks pblock_adc_clk] [get_cells -quiet u_adc_iq_rx_chain]
add_cells_to_pblock [get_pblocks pblock_adc_clk] [get_cells -quiet u_adc_iq_snapshot]
resize_pblock [get_pblocks pblock_adc_clk] -add SLR0
set_property IS_SOFT TRUE [get_pblocks pblock_adc_clk]

# Timing 38-436: if bus_skew constraints are present after implementation:
#   report_bus_skew -warn_on_violation
