# ============================================================
# VU13P ADDA 验证平台 — RTL 工程一键构建
# 用法: vivado -mode batch -source fpga/scripts/create_project.tcl
# 产物: ../vivado/rf_adda.xpr, Top=rf_adda_top
# 注: clk_wiz_0 / clk_wiz_1 / ILA IP 须在 Vivado 中按 rf_adda_top.v 注释配置后重新生成
# ============================================================

set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
set proj_dir   "$fpga_dir/vivado"
set part       xcvu13p-fhga2104-2-i

proc add_verilog_recursive {root} {
    foreach f [glob -nocomplain -directory $root -type f *.v] {
        add_files -norecurse $f
    }
    foreach d [glob -nocomplain -directory $root -type d *] {
        add_verilog_recursive $d
    }
}

create_project rf_adda $proj_dir -part $part -force

set pins_xdc "$fpga_dir/constraints/adda_io.xdc"
set pins_tpl "$fpga_dir/constraints/adda_io.template.xdc"
if {![file exists $pins_xdc]} {
    puts "ERROR: 缺少板级约束 $pins_xdc"
    puts "  请复制模板: cp fpga/constraints/adda_io.template.xdc fpga/constraints/adda_io.xdc"
    exit 1
}

add_verilog_recursive "$fpga_dir/rtl"

foreach mem [glob -nocomplain -directory "$fpga_dir/data" *.mem] {
    add_files -norecurse $mem
    set_property FILE_TYPE "Memory File" [get_files $mem]
}

add_files -fileset constrs_1 -norecurse $pins_xdc
add_files -fileset constrs_1 -norecurse "$fpga_dir/constraints/adda_clocks.xdc"
add_files -fileset constrs_1 -norecurse "$fpga_dir/constraints/adda_dac_ddr.xdc"

set_property top rf_adda_top [current_fileset]
update_compile_order -fileset sources_1

puts "=== ADDA RTL PROJECT OK (add clk_wiz_0/1 + ILA IP per rf_adda_top.v) ==="
