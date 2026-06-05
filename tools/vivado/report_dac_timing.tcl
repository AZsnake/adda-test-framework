# Report DAC DDR output timing after implementation.
# Usage (Vivado Tcl console, project open, impl_1 finished):
#   source tools/vivado/report_dac_timing.tcl
#
# Writes dac_timing_summary.rpt in the current directory.

set rpt dac_timing_summary.rpt
set fh [open $rpt w]

proc w {msg} {
  global fh
  puts $fh $msg
  puts $msg
}

w "=== DAC DDR timing summary ==="
w [clock format [clock seconds]]

if {[llength [get_clocks dac_dclkio -quiet]] == 0} {
  w "ERROR: clock dac_dclkio not found. Check adda_dac_ddr.xdc and top instance u_tx_ddr_out."
} else {
  w "\n--- dac_dclkio network ---"
  redirect -variable r {report_clock_networks -name dac_dclkio [get_clocks dac_dclkio]}
  w $r
}

set db_ports [get_ports {FPGA_DAC_DB[*]} -quiet]
if {$db_ports eq ""} {
  w "ERROR: no FPGA_DAC_DB ports found."
} else {
  w "\n--- setup/hold to FPGA_DAC_DB[*] (vs dac_dclkio) ---"
  redirect -variable r {
    report_timing -to $db_ports -delay_type min_max -sort_by slack -max_paths 20 -nworst 2
  }
  w $r
}

set dco_port [get_ports FPGA_DAC_DCLKIO -quiet]
if {$dco_port ne ""} {
  w "\n--- paths to FPGA_DAC_DCLKIO ---"
  redirect -variable r {
    report_timing -to $dco_port -delay_type min_max -sort_by slack -max_paths 10
  }
  w $r
}

if {[llength $db_ports] > 0} {
  w "\n--- bus skew (FPGA_DAC_DB) ---"
  redirect -variable r {report_bus_skew -warn_on_violation -include_hold}
  w $r
}

w "\n--- slack check (dac_dclkio-related endpoints) ---"
set paths [get_timing_paths -to $db_ports -max_paths 500 -setup -hold -quiet]
if {$paths eq ""} {
  w "No timing paths found to DB ports."
} else {
  set wns_setup 1e9
  set wns_hold  1e9
  foreach p $paths {
    set slack [get_property SLACK $p]
    set is_hold [get_property IS_HOLD $p]
    if {$is_hold} {
      if {$slack < $wns_hold} { set wns_hold $slack }
    } else {
      if {$slack < $wns_setup} { set wns_setup $slack }
    }
  }
  if {$wns_setup != 1e9} { w [format "WNS setup (DB): %.3f ns" $wns_setup] }
  if {$wns_hold  != 1e9} { w [format "WNS hold  (DB): %.3f ns" $wns_hold] }
  if {$wns_setup < 0 || $wns_hold < 0} {
    w "FAIL: negative slack — try DAC_DCLK_CLK_SEL phase sweep (see docs/dac_ddr_timing_bringup.md)."
  } else {
    w "PASS: no negative slack on sampled DB paths."
  }
}

close $fh
w "\nWrote $rpt"
