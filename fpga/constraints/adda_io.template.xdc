# rf_adda_top pin constraints — TEMPLATE ONLY (no real PACKAGE_PIN values).
#
# Copy to adda_io.xdc (gitignored) and fill from your board schematic:
#   copy constraints\adda_io.template.xdc constraints\adda_io.xdc
#
# Required port groups (must match rf_adda_top.v):
#   pad_clk_19m2_1, pad_adda_rstn
#   pad_si5340_* (csb, sclk, sda, sdo, oeb, rstb, intrb, lolb, losxb)
#   pad_adc_* / pad_dac_* (SPI)
#   FPGA_ADC_DCOA, FPGA_ADC_DA[13:0], FPGA_ADC_DB[13:0]
#   FPGA_DAC_CLKIN, FPGA_DAC_DCLKIO, FPGA_DAC_DB[13:0]
#   i_uart_rx, o_uart_tx
#   pad_led_red, pad_led_blue, pad_output_d[7:0], pad_input_s[7:0]
#
# Example (replace PACKAGE_PIN and IOSTANDARD per schematic):
# set_property -dict {PACKAGE_PIN XX00 IOSTANDARD LVCMOS18} [get_ports pad_clk_19m2_1]
