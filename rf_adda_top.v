// ADDA board bring-up top: UART command parser + SPI master (SI5340 / AD9640 / AD9117).
// Integrates RX IQ chain, DAC 2x-interpolated DDR TX, and on-chip boot FSM.
//------------------------------------------------------------------------------
// DAC TX is 2x-interpolated DDR only: 61.44 MSa/s/ch baseband -> tx_iq_dsp
// -> 122.88 MSa/s/ch -> 245.76 MSa/s interleaved bus (DCLKIO 122.88,
// I on rising / Q on falling = AD9117 IFIRST=1, IRISING=1).  REQUIRES:
// SI5340 OUT3 -> 122.88 MHz (AD9117 CLKIN), clk_wiz_0 @ 0 deg (sys_clk) +
// clk_wiz_1 seven 122.88 MHz taps @ 90..360 deg (45 deg steps). DCLKIO phase
// selected by pad_input_s[2:0] dip switches (default 000 = 90 deg). Scope
// DCLKIO vs FPGA_DAC_CLKIN to find optimal phase; see docs/dac_ddr_timing_bringup.md.
// Vivado: reconfigure clk_wiz_1 — 7 outputs, dynamic PS OFF (see module header).
// See docs/tx_interp2x_bringup.md.
module rf_adda_top #(
  parameter integer SYS_CLK_HZ = 122_880_000
) (
  input  wire        pad_clk_19m2_1,
  input  wire        pad_adda_rstn,

  input  wire        i_uart_rx,
  output wire        o_uart_tx,

  output wire        pad_si5340_csb,
  output wire        pad_si5340_sclk,
  output wire        pad_si5340_sda,
  input  wire        pad_si5340_sdo,
  output wire        pad_si5340_oeb,
  output wire        pad_si5340_rstb,
  input  wire        pad_si5340_intrb,
  input  wire        pad_si5340_lolb,
  input  wire        pad_si5340_losxb,

  output wire        pad_adc_csb,
  output wire        pad_adc_sclk,
  inout  wire        pad_adc_sdio,
  input  wire        pad_adc_smi_clk,
  input  wire        pad_adc_smi_dfs,
  input  wire        pad_adc_smi_sdo,

  // Phase-4: AD9640 parallel data capture (channel A=I, channel B=Q from board
  // analog IQ demod). DCOA gates both channels; DCOB is not used (same chip,
  // same internal clock). CMOS mode, two's complement.
  // SI5340 mapping: OUT0 = 122.88 MHz -> AD9640 sample clock.
  input  wire        FPGA_ADC_DCOA,       // data clock out from AD9640 DCOA (122.88 MHz, SI5340 OUT0)
  input  wire [13:0] FPGA_ADC_DA,         // 14-bit channel-A sample (I)
  input  wire [13:0] FPGA_ADC_DB,         // 14-bit channel-B sample (Q)

  output wire        pad_dac_csb,
  output wire        pad_dac_sclk,
  inout  wire        pad_dac_sdio,
  output wire        pad_dac_reset,

  // Phase-5: AD9117 parallel CMOS DDR output (IFIRST=1, IRISING=1).
  // SI5340 mapping: OUT3 = 122.88 MHz -> AD9117 CLKIN on board.
  input  wire        FPGA_DAC_CLKIN,     // SI5340 DAC clock monitor pin (optional in RTL)
  output wire [13:0] FPGA_DAC_DB,
  output wire        FPGA_DAC_DCLKIO,

  output wire        pad_led_red,
  output wire        pad_led_blue,
  output wire [7:0]  pad_output_d,

  // Dip switches: ON = high. pad_input_s[2:0] selects DCLKIO phase (000 = 90 deg).
  input  wire [7:0]  pad_input_s
);

  // Clock plan:
  //   clk_wiz_0: 19.2 MHz pad -> clk_out1 = 122.88 MHz @ 0deg. Drives DB ODDRE1,
  //              fabric, UART/SPI. NO dynamic phase shift.
  //   clk_wiz_1: clk_in1 = sys_clk (Source = "No buffer"), clk_out1..7 =
  //              122.88 MHz @ 90/135/180/225/270/315/360 deg. Dynamic PS OFF.
  //              dac_dclk_phase_mux (linear BUFGMUX chain) selects one tap for DCLKIO.
  //              pad_input_s[2:0] dip switches drive mux select (000 = 90 deg).
  // Vivado IP step (outside repo): reconfigure clk_wiz_1 per above, regenerate.
  wire sys_clk;
  wire sys_clk_locked;
  wire sys_clk_dco_locked;

  wire dco_clk_90, dco_clk_135, dco_clk_180, dco_clk_225;
  wire dco_clk_270, dco_clk_315, dco_clk_360;
  wire dac_dclk_clk;

  clk_wiz_0 u_sys_clk_wiz (
    .clk_out1 (sys_clk),
    .reset    (~pad_adda_rstn),
    .locked   (sys_clk_locked),
    .clk_in1  (pad_clk_19m2_1)
  );

  clk_wiz_1 u_dco_clk_wiz (
    .clk_out1 (dco_clk_90),
    .clk_out2 (dco_clk_135),
    .clk_out3 (dco_clk_180),
    .clk_out4 (dco_clk_225),
    .clk_out5 (dco_clk_270),
    .clk_out6 (dco_clk_315),
    .clk_out7 (dco_clk_360),
    .reset    (~pad_adda_rstn),
    .locked   (sys_clk_dco_locked),
    .clk_in1  (sys_clk)
  );

  dac_dclk_phase_mux u_dac_dclk_phase_mux (
    .clk_in0  (dco_clk_90),
    .clk_in1  (dco_clk_135),
    .clk_in2  (dco_clk_180),
    .clk_in3  (dco_clk_225),
    .clk_in4  (dco_clk_270),
    .clk_in5  (dco_clk_315),
    .clk_in6  (dco_clk_360),
    .clk_sel  (pad_input_s[2:0]),
    .clk_out  (dac_dclk_clk)
  );

  // ADC data clock (FPGA_ADC_DCOA from AD9640 122.88 MHz) -- must go through
  // IBUF + BUFG so Vivado routes it on the global clock network.
  // Skipping this causes the adc_clk domain FFs to miss edges and the
  // capture FSM to stay in IDLE (symptom: all BRAM reads return 0x00).
  wire adc_clk_ibuf;
  wire adc_clk;

  IBUF u_adc_clk_ibuf (
    .I (FPGA_ADC_DCOA),
    .O (adc_clk_ibuf)
  );

  BUFG u_adc_clk_bufg (
    .I (adc_clk_ibuf),
    .O (adc_clk)
  );

  wire        spi0_clk;
  wire        spi0_mosi;
  wire        spi0_oen;
  wire        spi0_cs;
  wire        spi0_miso1;

  wire        spi1_clk;
  wire        spi1_mosi;
  wire        spi1_oen;
  wire        spi1_cs;
  wire        spi1_miso0;

  wire        spi2_clk;
  wire        spi2_mosi;
  wire        spi2_oen;
  wire        spi2_cs;
  wire        spi2_miso0;

  wire [61:0] gpo;
  wire [31:0] o_et_ctrl;
  wire [31:0] reg_rdata;
  wire        reg_rdata_vld;

  wire        spi3_clk;
  wire        spi4_clk;
  wire        spi5_clk;
  wire        spi7_clk;
  wire        spi3_mosi;
  wire        spi4_mosi;
  wire        spi5_mosi;
  wire        spi7_mosi;
  wire        spi3_oen;
  wire        spi4_oen;
  wire        spi5_oen;
  wire        spi7_oen;
  wire        spi3_cs;
  wire        spi4_cs;
  wire        spi5_cs;
  wire        spi6_cs;
  wire        spi7_cs;

  assign pad_si5340_sclk = spi0_clk;
  assign pad_si5340_csb  = spi0_cs;
  assign pad_si5340_sda  = spi0_mosi;
  // spi0 bidirection=0 (4-wire): rf_spi_core samples spi0_miso1, not miso0
  assign spi0_miso1      = pad_si5340_sdo;

  assign pad_adc_sclk = spi1_clk;
  assign pad_adc_csb  = spi1_cs;
  // 3-wire SDIO: oen=0 drive instruction/data out; oen=1 tri-state for readback
  assign pad_adc_sdio = spi1_oen ? 1'bz : spi1_mosi;
  assign spi1_miso0   = pad_adc_sdio;

  assign pad_dac_sclk = spi2_clk;
  assign pad_dac_csb  = spi2_cs;
  assign pad_dac_sdio = spi2_oen ? 1'bz : spi2_mosi;
  assign spi2_miso0   = pad_dac_sdio;

  // Global reset pulse from UART command 0xF2 — stretched to ~10 ms so chip POR sees it
  wire        global_rst_pulse;
  reg  [19:0] grst_cnt;
  localparam integer GRST_CYCLES = SYS_CLK_HZ / 100;  // 10 ms @ SYS_CLK_HZ
  wire        grst_active = (grst_cnt != 20'd0);

  always @(posedge sys_clk or negedge pad_adda_rstn) begin
    if (!pad_adda_rstn)            grst_cnt <= 20'd0;
    else if (global_rst_pulse)     grst_cnt <= GRST_CYCLES[19:0];
    else if (grst_active)          grst_cnt <= grst_cnt - 1'b1;
  end

  assign pad_si5340_rstb = pad_adda_rstn & ~grst_active;
  // SI5340 SDA output enable: 0 = driver enabled (4-wire SPI, no tri-state on SDA out)
  assign pad_si5340_oeb  = 1'b0;
  // AD9117 RESET/PINMD: low = SPI (SDIO); high = pin mode. Invert board rstn,
  // and assert RESET (high) for the duration of the global-reset window.
  assign pad_dac_reset   = ~pad_adda_rstn | grst_active;

  // 0xF2 upgrade: on the falling edge of the hard-reset window, re-trigger
  // boot_fsm so chips get re-initialised from boot_rom (covers AD9640 which
  // has no dedicated reset pin and must be soft-reset via its init table).
  reg  grst_active_d;
  wire boot_retrigger = grst_active_d & ~grst_active;
  always @(posedge sys_clk or negedge pad_adda_rstn) begin
    if (!pad_adda_rstn) grst_active_d <= 1'b0;
    else                grst_active_d <= grst_active;
  end

  wire [2:0]  led_state;
  wire        led_frame_start;
  wire        led_spi_busy;
  wire [7:0]  led_last_chip;
  wire [7:0]  led_last_cmd;
  wire [7:0]  led_last_status;

  // boot_fsm status (from rf_ctrl_path) — wired to LED layer and ILA.
  wire        boot_busy;
  wire        boot_done;
  wire [3:0]  boot_chip;
  wire [7:0]  boot_err;

  // Board monitor inputs (SPI-side / IRQ — not datapath; satisfy Synth 8-7129)
  reg  si5340_intrb_r, adc_smi_clk_r, adc_smi_dfs_r, adc_smi_sdo_r;
  always @(posedge sys_clk or negedge pad_adda_rstn) begin
    if (!pad_adda_rstn) begin
      si5340_intrb_r <= 1'b0;
      adc_smi_clk_r  <= 1'b0;
      adc_smi_dfs_r  <= 1'b0;
      adc_smi_sdo_r  <= 1'b0;
    end else begin
      si5340_intrb_r <= pad_si5340_intrb;
      adc_smi_clk_r  <= pad_adc_smi_clk;
      adc_smi_dfs_r  <= pad_adc_smi_dfs;
      adc_smi_sdo_r  <= pad_adc_smi_sdo;
    end
  end

  // ADC snapshot wires — debug uses dedicated ILA IP wiring only.
  wire        adc_arm;
  wire        adc_done;
  wire        adc_busy;
  wire [13:0] adc_n;
  wire [13:0] adc_rd_addr;
  wire [13:0] adc_rdata;
  wire        adc_chan_sel;

  // New RX-chain controls
  wire [15:0] nco_freq_word;
  wire [1:0]  dec_ratio;
  wire        capture_mode;
  wire        iq_bypass;
  wire        fir_bypass;
  wire [1:0]  fir_sel;
  wire [15:0] iq_mult_op1;
  wire [15:0] iq_mult_op2;
  wire [13:0] iq_offset_i;
  wire [13:0] iq_offset_q;

  wire signed [13:0] rx_i;
  wire signed [13:0] rx_q;
  wire               rx_vld;
  wire               rx_fifo_afull;
  wire               rx_fifo_aempty;
  // adc_clk-domain direct tap (pre-FIFO) for snapshot
  wire signed [13:0] rx_adc_i;
  wire signed [13:0] rx_adc_q;
  wire               rx_adc_vld;

  wire [7:0] stream_byte;
  wire       stream_byte_vld;
  wire       stream_overflow;
  wire       stream_enable;
  wire       stream_byte_ready;

  // Phase-5: DAC tone generator (UART 0x40) + TX halfband bypass (0x41 bit[7])
  wire        dac_tone_en;
  wire [2:0]  dac_wave_sel;
  wire        dac_hb_bypass;
  wire [15:0] dac_freq_word;
  wire [7:0]  dac_amp_pct;
  // Force tone off during the 10 ms hard-reset window so DAC sees DC midscale
  // while AD9117 RESET is asserted and boot_fsm re-runs.
  wire        dac_tone_en_gated = dac_tone_en & ~grst_active;

  // Phase-5b: waveform player (UART 0x50/0x51/0x52)
  wire        wave_play_en;
  wire [17:0] wave_loop_len_minus1;
  wire        wave_swap_iq;
  wire        wave_neg_q;
  wire        wave_wr_en;
  wire [17:0] wave_wr_addr;
  wire [31:0] wave_wr_data;
  wire        wave_play_en_gated = wave_play_en & ~grst_active;

  // Parallel 16-bit I/Q @ 61.44 MSa/s/ch (pre-interp), feeding tx_iq_dsp.
  wire signed [15:0] tone_iq_i16, tone_iq_q16;
  wire               tone_iq_vld;
  wire signed [15:0] wave_iq_i16, wave_iq_q16;
  wire               wave_iq_vld;

  led_status #(
    .HB_DIV       (SYS_CLK_HZ / 2),
    .PING_DIV     (SYS_CLK_HZ / 10),   // ~100 ms/step; full 0→7→0 ~1.4 s
    .RESULT_TICKS (SYS_CLK_HZ),
    .OK_PHASE     (SYS_CLK_HZ / 8)
  ) u_led_status (
    .clk           (sys_clk),
    .rst_n         (pad_adda_rstn),
    .state         (led_state),
    .spi_busy      (led_spi_busy),
    .frame_start   (led_frame_start),
    .last_chip     (led_last_chip),
    .last_cmd      (led_last_cmd),
    .last_status   (led_last_status),
    .boot_busy     (boot_busy),
    .boot_chip     (boot_chip),
    .boot_err      (boot_err),
    .led_red       (pad_led_red),
    .led_blue      (pad_led_blue),
    .strip         (pad_output_d)
  );

  rf_ctrl_path #(
    .CLK_HZ (SYS_CLK_HZ)
  ) u_rf_ctrl_path (
    .clk            (sys_clk),
    .config_clk     (sys_clk),
    .rst_n          (pad_adda_rstn),
    .i_config_rst_n (pad_adda_rstn),
    .soft_reset     (1'b0),
    .i_gp_trigger   ({28'h0, si5340_intrb_r, adc_smi_clk_r, adc_smi_dfs_r, adc_smi_sdo_r}),

    .reg_wr         (1'b0),
    .reg_rd         (1'b0),
    .reg_addr       (15'h0),
    .reg_wdata      (32'h0),
    .reg_rdata      (reg_rdata),
    .reg_rdata_vld  (reg_rdata_vld),

    .spi0_miso0     (1'b0),
    .spi0_miso1     (spi0_miso1),
    .spi1_miso0     (spi1_miso0),
    .spi2_miso0     (spi2_miso0),
    .spi3_miso0     (1'b0),
    .spi4_miso0     (1'b0),
    .spi5_miso0     (1'b0),
    .spi7_miso0     (1'b0),

    .spi1_miso1     (1'b0),
    .spi2_miso1     (1'b0),
    .spi3_miso1     (1'b0),
    .spi4_miso1     (1'b0),
    .spi5_miso1     (1'b0),
    .spi7_miso1     (1'b0),

    .spi0_clk       (spi0_clk),
    .spi1_clk       (spi1_clk),
    .spi2_clk       (spi2_clk),
    .spi3_clk       (spi3_clk),
    .spi4_clk       (spi4_clk),
    .spi5_clk       (spi5_clk),
    .spi7_clk       (spi7_clk),

    .spi0_mosi      (spi0_mosi),
    .spi1_mosi      (spi1_mosi),
    .spi2_mosi      (spi2_mosi),
    .spi3_mosi      (spi3_mosi),
    .spi4_mosi      (spi4_mosi),
    .spi5_mosi      (spi5_mosi),
    .spi7_mosi      (spi7_mosi),

    .spi0_oen       (spi0_oen),
    .spi1_oen       (spi1_oen),
    .spi2_oen       (spi2_oen),
    .spi3_oen       (spi3_oen),
    .spi4_oen       (spi4_oen),
    .spi5_oen       (spi5_oen),
    .spi7_oen       (spi7_oen),

    .spi0_cs        (spi0_cs),
    .spi1_cs        (spi1_cs),
    .spi2_cs        (spi2_cs),
    .spi3_cs        (spi3_cs),
    .spi4_cs        (spi4_cs),
    .spi5_cs        (spi5_cs),
    .spi6_cs        (spi6_cs),
    .spi7_cs        (spi7_cs),

    .i_uart_rx      (i_uart_rx),
    .o_uart_tx      (o_uart_tx),

    .o_led_state       (led_state),
    .o_led_frame_start (led_frame_start),
    .o_led_last_chip   (led_last_chip),
    .o_led_last_cmd    (led_last_cmd),
    .o_led_last_status (led_last_status),
    .o_led_spi_busy    (led_spi_busy),
    .o_global_rst      (global_rst_pulse),

    .i_si5340_lolb     (pad_si5340_lolb),
    .i_si5340_losxb    (pad_si5340_losxb),
    .i_boot_start_ext  (boot_retrigger),
    .o_boot_busy       (boot_busy),
    .o_boot_done       (boot_done),
    .o_boot_chip       (boot_chip),
    .o_boot_err        (boot_err),

    .o_adc_arm         (adc_arm),
    .o_adc_n           (adc_n),
    .o_adc_rd_addr     (adc_rd_addr),
    .o_adc_chan_sel    (adc_chan_sel),
    .i_adc_done        (adc_done),
    .i_adc_busy        (adc_busy),
    .i_adc_rdata       (adc_rdata),
    .o_dac_tone_en     (dac_tone_en),
    .o_dac_wave_sel    (dac_wave_sel),
    .o_dac_hb_bypass   (dac_hb_bypass),
    .o_dac_freq_word   (dac_freq_word),
    .o_dac_amp_pct     (dac_amp_pct),
    .o_dac_dclk_ps_target (),
    .o_nco_freq_word   (nco_freq_word),
    .o_dec_ratio       (dec_ratio),
    .o_capture_mode    (capture_mode),
    .o_iq_bypass       (iq_bypass),
    .o_fir_bypass      (fir_bypass),
    .o_fir_sel         (fir_sel),
    .o_iq_mult_op1     (iq_mult_op1),
    .o_iq_mult_op2     (iq_mult_op2),
    .o_iq_offset_i     (iq_offset_i),
    .o_iq_offset_q     (iq_offset_q),
    .i_stream_byte     (stream_byte),
    .i_stream_byte_vld (stream_byte_vld),
    .i_stream_overflow (stream_overflow),
    .o_stream_enable   (stream_enable),
    .o_stream_byte_ready(stream_byte_ready),

    .o_wave_play_en         (wave_play_en        ),
    .o_wave_loop_len_minus1 (wave_loop_len_minus1),
    .o_wave_swap_iq         (wave_swap_iq        ),
    .o_wave_neg_q           (wave_neg_q          ),
    .o_wave_wr_en           (wave_wr_en          ),
    .o_wave_wr_addr         (wave_wr_addr        ),
    .o_wave_wr_data         (wave_wr_data        ),

    .gpo            (gpo),
    .o_et_ctrl      (o_et_ctrl),
    .T_RWM          (3'b0)
  );

  // DAC sample sources @ 61.44 MSa/s/ch -> unified tx_iq_dsp 2x interp -> DDR.
  dac_tone_gen u_dac_tone (
    .i_clk     (sys_clk),
    .i_rst_n   (pad_adda_rstn),
    .i_tone_en (dac_tone_en_gated),
    .i_wave_sel(dac_wave_sel),
    .i_freq_word(dac_freq_word),
    .i_amp_pct (dac_amp_pct),
    .o_iq_i16  (tone_iq_i16),
    .o_iq_q16  (tone_iq_q16),
    .o_iq_vld  (tone_iq_vld)
  );

  dac_wave_player u_dac_wave (
    .i_clk             (sys_clk),
    .i_rst_n           (pad_adda_rstn),
    .i_play_en         (wave_play_en_gated),
    .i_loop_len_minus1 (wave_loop_len_minus1),
    .i_swap_iq         (wave_swap_iq),
    .i_neg_q           (wave_neg_q),
    .i_wr_en           (wave_wr_en),
    .i_wr_addr         (wave_wr_addr),
    .i_wr_data         (wave_wr_data),
    .o_iq_i16          (wave_iq_i16),
    .o_iq_q16          (wave_iq_q16),
    .o_iq_vld          (wave_iq_vld)
  );

  wire signed [15:0] bb_i16, bb_q16;
  wire               bb_vld;
  assign bb_vld = wave_play_en_gated ? wave_iq_vld : tone_iq_vld;
  assign bb_i16 = wave_play_en_gated ? wave_iq_i16 : tone_iq_i16;
  assign bb_q16 = wave_play_en_gated ? wave_iq_q16 : tone_iq_q16;

  wire               dsp_vld;
  wire signed [13:0] dsp_i, dsp_q;
  tx_iq_dsp u_tx_iq_dsp (
    .i_clk      (sys_clk),
    .i_rst_n    (pad_adda_rstn),
    .i_in_vld   (bb_vld),
    .i_hb_bypass(dac_hb_bypass),
    .i_dc_test  ((dac_wave_sel == 3'd4) & dac_tone_en_gated),
    .i_i        (bb_i16),
    .i_q        (bb_q16),
    .o_vld   (dsp_vld),
    .o_i     (dsp_i),
    .o_q     (dsp_q)
  );

  tx_ddr_out u_tx_ddr_out (
    .i_clk      (sys_clk),
    .i_clk_dco  (dac_dclk_clk),
    .i_rst      (grst_active),
    .i_i        (dsp_i),
    .i_q        (dsp_q),
    .o_dac_db   (FPGA_DAC_DB),
    .o_dac_dclkio(FPGA_DAC_DCLKIO)
  );

  adc_iq_rx_chain u_adc_iq_rx_chain (
    .i_adc_clk       (adc_clk),
    .i_sys_clk       (sys_clk),
    .i_rst_n         (pad_adda_rstn),
    .i_adc_i         (FPGA_ADC_DA),
    .i_adc_q         (FPGA_ADC_DB),
    .i_dec_ratio     (dec_ratio),
    .i_nco_freq_word (nco_freq_word),
    .i_iq_bypass     (iq_bypass),
    .i_iq_mult_op1   (iq_mult_op1),
    .i_iq_mult_op2   (iq_mult_op2),
    .i_iq_offset_i   (iq_offset_i),
    .i_iq_offset_q   (iq_offset_q),
    .i_fir_bypass    (fir_bypass),
    .i_fir_sel       (fir_sel),
    .o_iq_i          (rx_i),
    .o_iq_q          (rx_q),
    .o_iq_vld        (rx_vld),
    .o_fifo_almst_full (rx_fifo_afull),
    .o_fifo_almst_empty(rx_fifo_aempty),
    .o_adc_iq_i      (rx_adc_i),
    .o_adc_iq_q      (rx_adc_q),
    .o_adc_iq_vld    (rx_adc_vld)
  );

  adc_iq_snapshot u_adc_iq_snapshot (
    .i_sys_clk   (sys_clk),
    .i_rst_n     (pad_adda_rstn),
    .i_arm       (adc_arm),
    .i_n_samples (adc_n),
    .i_rd_addr   (adc_rd_addr),
    .i_chan_sel  (adc_chan_sel),
    .o_rd_data   (adc_rdata),
    .o_done      (adc_done),
    .o_busy      (adc_busy),
    .i_adc_clk   (adc_clk),
    .i_iq_i      (rx_adc_i),
    .i_iq_q      (rx_adc_q),
    .i_iq_vld    (rx_adc_vld)
  );

  adc_iq_stream_drain u_adc_iq_stream_drain (
    .i_clk          (sys_clk),
    .i_rst_n        (pad_adda_rstn),
    .i_enable       (stream_enable),
    .i_iq_i         (rx_i),
    .i_iq_q         (rx_q),
    .i_iq_vld       (rx_vld),
    .o_byte         (stream_byte),
    .o_byte_vld     (stream_byte_vld),
    .i_byte_ready   (stream_byte_ready),
    .o_overflow     (stream_overflow)
  );

// ---- ILA debug cores (enabled by FPGA_DEBUG_RF define) -------------------
// Vivado: Settings → Verilog options → add FPGA_DEBUG_RF; create all ILA IPs;
// program .bit + .ltx from the same impl_1 run (see constraints/adda_clocks.xdc).
//   ila_adda_sys : probe0 width = 91, depth = 4096, clk = sys_clk
//     [90:83] pad_input_s, [82] sys_clk_dco_locked, [81:70] reserved
//   ila_adda_adc : probe0 width = 64, depth = 4096, clk = adc_clk
//   ila_adda_dac : probe0 width = 47, depth = 4096, clk = sys_clk     (pre-ODDRE1)
//   ila_adda_ddr : REMOVED — UltraScale+ OLOGIC has no fabric loopback
// Synth 8-4446 (ILA has no output ports) is expected and harmless.
`ifdef FPGA_DEBUG_RF

// -- ILA 0: sys_clk domain (122.88 MHz) — SPI x3 + UART + ADC control ------
ila_adda_sys u_ila_sys (
  .clk    (sys_clk),           // input wire clk
  .probe0 ({                   // input wire [90:0] probe0
    pad_input_s[7:0],                                // [90:83] dip switch state
    sys_clk_dco_locked,                              // [82]    clk_wiz_1 MMCM locked
    12'd0,                                           // [81:70] reserved
    u_rf_ctrl_path.u_uart_cmd_parser.state[3:0],     // [69:66]
    u_rf_ctrl_path.u_uart_cmd_parser.sub_idx[1:0],   // [65:64]
    u_rf_ctrl_path.u_uart_cmd_parser.ack_data[7:0],  // [63:56]
    spi0_clk,                                  // [54]    SI5340 SCLK
    spi0_cs,                                   // [53]    SI5340 CSB
    spi0_mosi,                                 // [52]    SI5340 SDA out
    spi0_oen,                                  // [51]    SI5340 turnaround
    pad_si5340_sdo,                            // [50]    SI5340 SDO in
    u_rf_ctrl_path.spi_rdata[47:40],           // [49:42] SPI read-back byte
    adc_rdata[13:0],                           // [41:28] ADC BRAM read data (14 bit)
    adc_n[11:0],                               // [27:16] capture length
    spi2_clk, spi2_cs, spi2_mosi,              // [15:13] AD9117 SPI
    spi2_oen, spi2_miso0,                      // [12:11]
    spi1_clk, spi1_cs, spi1_mosi,              // [10:8]  AD9640 SPI
    spi1_oen, spi1_miso0,                      // [7:6]
    u_rf_ctrl_path.spi_cmd_done,               // [5]
    u_rf_ctrl_path.spi_start_mux,              // [4]
    u_rf_ctrl_path.uart_busy,                  // [3]
    adc_arm, adc_busy, adc_done                // [2:0]
  })
);

// -- ILA 1: adc_clk domain (122.88 MHz) -- RX chain / DAC loopback ---------
// Probes use the post-IOB-FF registers (adc_i_r / adc_q_r) instead of the raw
// pad nets (FPGA_ADC_DA / FPGA_ADC_DB), because the pad-to-IOB-FF net is
// internal to the IOB tile and cannot be tapped for debug (Chipscope 16-3).
// The data is identical, delayed by 1 adc_clk cycle.
ila_adda_adc u_ila_adc (
  .clk    (adc_clk),           // input wire clk
  .probe0 ({                   // input wire [63:0] probe0
    u_adc_iq_rx_chain.adc_i_r[13:0],               // [63:50] DA post-IOB FF (ch A = I)
    u_adc_iq_rx_chain.adc_q_r[13:0],               // [49:36] DB post-IOB FF (ch B = Q)
    rx_adc_i[13:0],                                 // [35:22] snapshot-input I (post RX)
    rx_adc_q[13:0],                                 // [21:8]  snapshot-input Q (post RX)
    rx_adc_vld,                                     // [7]     snapshot-input valid
    rx_fifo_afull,                                  // [6]
    rx_fifo_aempty,                                 // [5]
    stream_overflow,                                // [4]
    dec_ratio[1:0],                                 // [3:2]
    capture_mode,                                   // [1]
    rx_vld                                          // [0]     sys_clk-side rx valid
  })
);

// -- ILA 2: sys_clk domain (122.88 MHz) — DAC data path (2x-interp DDR) ----
// Goal: prove the DIGITAL sample stream into the AD9117 is clean, so distortion
// can be attributed to the data path vs. the analog/clock side.
//
// The pre-ODDRE1 parallel I/Q taps (dsp_i/dsp_q @122.88/ch) avoid loading DB pads.
ila_adda_dac u_ila_dac (
  .clk    (sys_clk),
  .probe0 ({
    dsp_i,
    dsp_q,
    bb_i16[13:0],
    bb_vld,
    wave_play_en_gated,
    tone_iq_vld,
    dac_tone_en_gated,
    dac_wave_sel[2]
  })
);

`endif

endmodule
