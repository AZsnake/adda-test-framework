// Copyright (c) 2007-2012, INNOFIDEI Technologies. All Rights Reserved.
// INNOFIDEI Confidential Proprietary
// --------------------------------------------------------------------------
// FILE NAME : rf_ctrl_path.v
// AUTHOR :: zhaop
// -----------------------------------------------------------------------------
// RELEASE HISTORY
// VERSION    DATE          AUTHOR            DESCRIPTION
// 1.0        2011-12-23     zhaop
// -----------------------------------------------------------------------------
// PURPOSE :
// -----------------------------------------------------------------------------
// Clock Domains :
// Other :
// -FHDR------------------------------------------------------------------------
//------------------------------------------------------------------------------
// Module Declaration
//------------------------------------------------------------------------------
module rf_ctrl_path #(
  parameter integer CLK_HZ         = 50_000_000,
  parameter integer BOOT_ROM_DEPTH = 512,
  parameter         BOOT_MEM_FILE  = "boot_rom.mem"
) (
      i_si5340_lolb,
      i_si5340_losxb,
      i_boot_start_ext,
      o_boot_busy  ,
      o_boot_done  ,
      o_boot_chip  ,
      o_boot_err   ,
      o_adc_arm    ,
      o_adc_n      ,
      o_adc_rd_addr,
      o_adc_chan_sel,
      i_adc_done   ,
      i_adc_busy   ,
      i_adc_rdata  ,
      o_dac_tone_en,
      o_dac_wave_sel,
      o_dac_hb_bypass,
      o_dac_freq_word,
      o_dac_amp_pct,
      o_dac_dclk_ps_target,
      o_nco_freq_word,
      o_dec_ratio,
      o_capture_mode,
      o_iq_bypass,
      o_fir_bypass,
      o_fir_sel,
      o_iq_mult_op1,
      o_iq_mult_op2,
      o_iq_offset_i,
      o_iq_offset_q,
      i_stream_byte,
      i_stream_byte_vld,
      i_stream_overflow,
      o_stream_enable,
      o_stream_byte_ready,
      o_wave_play_en,
      o_wave_loop_len_minus1,
      o_wave_swap_iq,
      o_wave_neg_q,
      o_wave_wr_en,
      o_wave_wr_addr,
      o_wave_wr_data,
  //globals
      clk           ,
      config_clk    ,
      rst_n         ,
      i_config_rst_n,
  //
      soft_reset    ,
      i_gp_trigger  , // trigger input
  //config bus
  reg_wr            ,
  reg_rd            ,
  reg_addr          ,
  reg_wdata         ,
  reg_rdata         ,
  reg_rdata_vld     ,
  //spi port
      spi0_miso0    ,
      spi1_miso0    ,
      spi2_miso0    ,
      spi3_miso0    ,
      spi4_miso0    ,
      spi5_miso0    ,
      spi7_miso0    ,

      spi0_miso1    ,
      spi1_miso1    ,
      spi2_miso1    ,
      spi3_miso1    ,
      spi4_miso1    ,
      spi5_miso1    ,
      spi7_miso1    ,

      spi0_clk      ,
      spi1_clk      ,
      spi2_clk      ,
      spi3_clk      ,
      spi4_clk      ,
      spi5_clk      ,
      spi7_clk      ,

      spi0_mosi     ,
      spi1_mosi     ,
      spi2_mosi     ,
      spi3_mosi     ,
      spi4_mosi     ,
      spi5_mosi     ,
      spi7_mosi     ,


      spi0_oen      ,
      spi1_oen      ,
      spi2_oen      ,
      spi3_oen      ,
      spi4_oen      ,
      spi5_oen      ,
      spi7_oen      ,

      spi0_cs       ,
      spi1_cs       ,
      spi2_cs       ,
      spi3_cs       ,
      spi4_cs       ,
      spi5_cs       ,
      spi6_cs       ,
      spi7_cs       ,

  // UART command port (PC)
      i_uart_rx     ,
      o_uart_tx     ,

  // UART parser LED observability (rf_adda_top)
      o_led_state       ,
      o_led_frame_start ,
      o_led_last_chip   ,
      o_led_last_cmd    ,
      o_led_last_status ,
      o_led_spi_busy    ,

  // UART command 0xF2 global-reset request (1-cycle pulse @ clk)
      o_global_rst      ,

  //output
      gpo           ,
      o_et_ctrl     ,
      T_RWM
  );


//------------------------------------------------------------------------------
// Inputs / Outputs
//------------------------------------------------------------------------------
//globals
  input         clk           ;
  input         config_clk    ;
  input         rst_n         ;
  input         i_config_rst_n;
  input         soft_reset    ;
  input  [31:0] i_gp_trigger  ; // trigger input
//config bus
  input             reg_wr      ;
  input             reg_rd      ;
  input  [14:0] reg_addr      ;
  input  [31:0] reg_wdata     ;
  output [31:0] reg_rdata     ;
  output            reg_rdata_vld;
//spi port
  input         spi0_miso0    ;
  input         spi1_miso0    ;
  input         spi2_miso0    ;
  input         spi3_miso0    ;
  input         spi4_miso0    ;
  input         spi5_miso0    ;
  input         spi7_miso0    ;
  input         spi0_miso1    ;
  input         spi1_miso1    ;
  input         spi2_miso1    ;
  input         spi3_miso1    ;
  input         spi4_miso1    ;
  input         spi5_miso1    ;
  input         spi7_miso1    ;

  output        spi0_clk      ;
  output        spi1_clk      ;
  output        spi2_clk      ;
  output        spi3_clk      ;
  output        spi4_clk      ;
  output        spi5_clk      ;
  output        spi7_clk      ;

  output        spi0_mosi     ;
  output        spi1_mosi     ;
  output        spi2_mosi     ;
  output        spi3_mosi     ;
  output        spi4_mosi     ;
  output        spi5_mosi     ;
  output        spi7_mosi     ;

  output        spi0_oen      ;
  output        spi1_oen      ;
  output        spi2_oen      ;
  output        spi3_oen      ;
  output        spi4_oen      ;
  output        spi5_oen      ;
  output        spi7_oen      ;

  output        spi0_cs       ;
  output        spi1_cs       ;
  output        spi2_cs       ;
  output        spi3_cs       ;
  output        spi4_cs       ;
  output        spi5_cs       ;
  output        spi6_cs       ;
  output        spi7_cs       ;

  input         i_uart_rx     ;
  output        o_uart_tx     ;

  output [2:0]  o_led_state       ;
  output        o_led_frame_start ;
  output [7:0]  o_led_last_chip   ;
  output [7:0]  o_led_last_cmd    ;
  output [7:0]  o_led_last_status ;
  output        o_led_spi_busy    ;
  output        o_global_rst      ;

  input         i_si5340_lolb     ;
  input         i_si5340_losxb    ;
  input         i_boot_start_ext  ;
  output        o_adc_arm         ;
  output [13:0] o_adc_n           ;
  output [13:0] o_adc_rd_addr     ;
  output        o_adc_chan_sel    ;
  input         i_adc_done        ;
  input         i_adc_busy        ;
  input  [13:0] i_adc_rdata       ;
  output        o_boot_busy       ;
  output        o_boot_done       ;
  output [3:0]  o_boot_chip       ;
  output [7:0]  o_boot_err        ;
  output        o_dac_tone_en     ;
  output [2:0]  o_dac_wave_sel    ;
  output        o_dac_hb_bypass   ;
  output [15:0] o_dac_freq_word   ;
  output [7:0]  o_dac_amp_pct     ;
  output [15:0] o_dac_dclk_ps_target ;
  output [15:0] o_nco_freq_word   ;
  output [1:0]  o_dec_ratio       ;
  output        o_capture_mode     ;
  output        o_iq_bypass        ;
  output        o_fir_bypass       ;
  output [1:0]  o_fir_sel          ;
  output [15:0] o_iq_mult_op1      ;
  output [15:0] o_iq_mult_op2      ;
  output [13:0] o_iq_offset_i      ;
  output [13:0] o_iq_offset_q      ;
  input  [7:0]  i_stream_byte      ;
  input         i_stream_byte_vld  ;
  input         i_stream_overflow  ;
  output        o_stream_enable    ;
  output        o_stream_byte_ready;

  // Waveform player (0x50/0x51/0x52)
  output        o_wave_play_en         ;
  output [17:0] o_wave_loop_len_minus1 ;
  output        o_wave_swap_iq         ;
  output        o_wave_neg_q           ;
  output        o_wave_wr_en           ;
  output [17:0] o_wave_wr_addr         ;
  output [31:0] o_wave_wr_data         ;

//output
  output [61:0] gpo           ;
  output [31:0] o_et_ctrl     ;
  input   [2:0] T_RWM         ;

//------------------------------------------------------------------------------
//internal signals
//------------------------------------------------------------------------------
  wire        soft_set_gpo1        ;
  wire [30:0] soft_gpo1            ;
  wire        soft_set_gpo2        ;
  wire [30:0] soft_gpo2            ;
  wire        spi_trigger_valid    ;
  wire  [4:0] spi_trigger_num      ;
  wire [16:0] spi_trigger_cmd      ;
  wire [31:0] spi_trigger_req      ;
  wire        spi_cmd_done         ;
  wire        gpo_trigger_valid    ;
  wire  [4:0] gpo_trigger_num      ;
  wire [31:0] gpo_trigger_req      ;
  wire [16:0] gpo_trigger_cmd      ;
  wire  [5:0] spi_frame_size       ;
  wire        spi_bidirection      ;
  wire  [4:0] spi_rd_switch_point  ;
  wire        spi_cpol             ;
  wire        spi_cpha             ;
  wire  [6:0] spi_split_interval   ;
  wire        gposram_read_valid   ;
  wire        gposram_ram_ack      ;
  wire  [8:0] gposram_read_addr    ;
  wire [31:0] gposram_rdata        ;
  wire        gposram_rdata_valid  ;
  wire        spisram_read_valid   ;
  wire        spisram_write_valid  ;
  wire        spisram_ram_ack      ;
  wire  [8:0] spisram_read_addr    ;
  wire  [8:0] spisram_write_addr   ;
  wire [31:0] spisram_wdata        ;
  wire [31:0] spisram_rdata        ;
  wire        spisram_rdata_valid  ;

  wire        cpu_sram_wr          ;
  wire        cpu_sram_rd          ;
  wire  [8:0] cpu_sram_addr        ;
  wire [31:0] cpu_sram_wdata       ;
  wire [31:0] cpu_sram_rdata       ;
  wire [62:0] spi_iir              ;
  wire        spi_iir_en           ;
  wire        spi_iir_done         ;
  wire [16:0] spi_batch_cmd        ;
  wire        spi_batch_en         ;
  wire        spi_batch_done       ;
  wire [62:0] spi_cmd              ;
  wire [55:0] spi_rdata            ;
  wire [55:0] spi_iir_rdata        ;
  wire [14:0] spi_rclk_div         ;
  wire [14:0] spi_wclk_div         ;
  wire [31:0] spram_wdata          ;
  wire [31:0] spram_rdata          ;
  wire        spi_capture_delay_sel;
  wire        spi_trigger_done     ;
  wire  [4:0] spi_trigger_done_num ;
  wire        gpo_trigger_done     ;
  wire  [4:0] gpo_trigger_done_num ;
  wire  [8:0] spram_addr           ;
  wire  [3:0] spi_cmd_currentstate ;
  wire  [2:0] gpo_cmd_currentstate ;
  wire        acp_mode             ;
  wire        spi_cmd_valid        ;
  wire        uart_spi_valid       ;
  wire [62:0] uart_spi_cmd         ;
  wire        uart_busy            ;
  wire        spi_start_mux        ;
  wire [62:0] spi_cmd_mux          ;

  // Boot infrastructure
  wire        boot_busy            ;
  wire        boot_done_sticky     ;
  wire        boot_done_pulse      ;
  wire [3:0]  boot_chip            ;
  wire [7:0]  boot_err             ;
  wire        boot_start_uart      ;
  wire        boot_start           = boot_start_uart | i_boot_start_ext;
  wire        boot_spi_valid       ;
  wire [62:0] boot_spi_cmd         ;
  wire [$clog2(BOOT_ROM_DEPTH)-1:0] boot_rom_addr;
  wire [31:0] boot_rom_data        ;
  wire        boot_spi_done        = boot_busy & spi_cmd_done; // private done channel

//------------------------------------------------------------------------------
//beginning main code
//------------------------------------------------------------------------------
 rf_ctrl_reg u_rf_ctrl_reg
(
//globals
  .clk                   (clk           ),
  .config_clk            (config_clk    ),
  .rst_n                 (i_config_rst_n),
//
  .i_gp_trigger          (i_gp_trigger),  //trigger input
  .gpo                   (gpo         ),
//config bus
  .reg_wr                (reg_wr       ),
  .reg_rd                (reg_rd       ),
  .reg_addr              (reg_addr[14:0]  ),
  .reg_wdata             (reg_wdata    ),
  .reg_rdata             (reg_rdata    ),
  .reg_rdata_vld         (reg_rdata_vld),
//output
  .soft_set_gpo1         (soft_set_gpo1)    ,
  .soft_gpo1             (soft_gpo1    )    ,
  .soft_set_gpo2         (soft_set_gpo2)    ,
  .soft_gpo2             (soft_gpo2    )    ,
//
  .spi_trigger_valid     (spi_trigger_valid     ),
  .spi_trigger_num       (spi_trigger_num       ),
  .spi_trigger_cmd       (spi_trigger_cmd      ),
  .spi_trigger_req       (spi_trigger_req       ),
  .spi_trigger_done      (spi_trigger_done          ),
  .spi_trigger_done_num  (spi_trigger_done_num           ),
  .gpo_trigger_valid     (gpo_trigger_valid     ),
  .gpo_trigger_num       (gpo_trigger_num       ),
  .gpo_trigger_cmd       (gpo_trigger_cmd       ),
  .gpo_trigger_req       (gpo_trigger_req       ),
  .gpo_trigger_done      (gpo_trigger_done          ),
  .gpo_trigger_done_num  (gpo_trigger_done_num           ),
//
  .spi_slave_sel         (spi_cmd_mux[62:60]     ),
  .spi_acp_frmsize       (spi_cmd_mux[55:50]     ),
  .spi_acp_swpoint       (spi_cmd_mux[49:45]     ),
  .spi_frame_size        (spi_frame_size     ),
  .spi_bidirection       (spi_bidirection    ),
  .spi_rd_switch_point   (spi_rd_switch_point),
  .spi_cpol              (spi_cpol           ),
  .spi_cpha              (spi_cpha           ),
  .spi_split_interval    (spi_split_interval ),
  .spi_capture_delay_sel (spi_capture_delay_sel),
  .cpu_sram_wr           (cpu_sram_wr   ),
  .cpu_sram_rd           (cpu_sram_rd   ),
  .cpu_sram_addr         (cpu_sram_addr ),
  .cpu_sram_wdata        (cpu_sram_wdata),
  .cpu_sram_rdata        (cpu_sram_rdata),
  .acp_mode              (acp_mode),

  .spi_iir                 (spi_iir     ),
  .spi_iir_en              (spi_iir_en  ),
  .spi_iir_done            (spi_iir_done) ,
  .spi_iir_rdata     (spi_iir_rdata),

  .spi_batch_cmd     (spi_batch_cmd     ),
  .spi_batch_en      (spi_batch_en  ),
  .spi_batch_done    (spi_batch_done),

  .spi_rclk_div         (spi_rclk_div),
  .spi_wclk_div         (spi_wclk_div),
  .spi_cmd_currentstate (spi_cmd_currentstate),
  .gpo_cmd_currentstate (gpo_cmd_currentstate),
  .o_et_ctrl           (o_et_ctrl)

);

rf_cmd_arb u_rf_cmd_arb_spi
(
//input
  .trigger_req        (spi_trigger_req),
//output
  .trigger_valid      (spi_trigger_valid),
  .trigger_num        (spi_trigger_num)
);

rf_cmd_arb u_rf_cmd_arb_gpo
(
//input
  .trigger_req        (gpo_trigger_req),
//output
  .trigger_valid      (gpo_trigger_valid),
  .trigger_num        (gpo_trigger_num)
);

spi_cmd_state u_spi_cmd_state
(
//globals
  .clk               (clk  ),
  .rst_n             (rst_n),
//input
  .soft_reset        (soft_reset),
  .trigger_valid     (spi_trigger_valid   ),
  .trigger_cmd       (spi_trigger_cmd    ),
  .trigger_num       (spi_trigger_num    ),
  .spi_split_interval    (spi_split_interval ),

  .spi_iir           (spi_iir     ),
  .spi_iir_en        (spi_iir_en  ),
  .spi_iir_done      (spi_iir_done),
  .spi_iir_rdata     (spi_iir_rdata),

  .spi_batch_cmd     (spi_batch_cmd     ),
  .spi_batch_en      (spi_batch_en  ),
  .spi_batch_done    (spi_batch_done),

  .ram_ack           (spisram_ram_ack        ),
  .ram_read_addr     (spisram_read_addr      ),
  .ram_rdata         (spisram_rdata          ),
  .ram_rdata_valid   (spisram_rdata_valid    ),
  .ram_read_valid    (spisram_read_valid     ),
  .ram_write_valid   (spisram_write_valid    ),
  .ram_write_addr    (spisram_write_addr     ),
  .ram_wdata         (spisram_wdata          ),
  .spi_cmd_valid     (spi_cmd_valid      ),
  .spi_cmd           (spi_cmd            ),
  .spi_cmd_done      (spi_cmd_done       ),
  .trigger_done      (spi_trigger_done   ),
  .trigger_done_num  (spi_trigger_done_num        ),
  .spi_rdata         (acp_mode ? {spi_frame_size[5:0], spi_rd_switch_point[4:0], 5'b0, spi_rdata[55:16]} : spi_rdata          ) ,
  .spi_cmd_currentstate (spi_cmd_currentstate)
);

 gpo_cmd_state  u_gpo_cmd_state
(
//globals
  .clk               (clk  ),
  .rst_n             (rst_n),
//input
  .soft_reset        (soft_reset),
  .trigger_valid     (gpo_trigger_valid),
  .trigger_cmd       (gpo_trigger_cmd  ),
  .trigger_num       (gpo_trigger_num    ),
  .ram_ack           (gposram_ram_ack      ),
  .ram_read_addr     (gposram_read_addr    ),
  .ram_rdata         (gposram_rdata        ),
  .ram_rdata_valid   (gposram_rdata_valid  ),
  .ram_read_valid    (gposram_read_valid   ),

  .trigger_done      (gpo_trigger_done          ),
  .trigger_done_num  (gpo_trigger_done_num           ),

  .soft_set_gpo1     (soft_set_gpo1),
  .soft_gpo1         (soft_gpo1    ),
  .soft_set_gpo2     (soft_set_gpo2),
  .soft_gpo2         (soft_gpo2    ),
  .gpo               (gpo          ),
  .gpo_cmd_currentstate (gpo_cmd_currentstate)
);

uart_cmd_parser #(
  .CLK_HZ (CLK_HZ)
  )
  u_uart_cmd_parser(
    .clk       (clk           ),
    .rst_n     (rst_n         ),
    .uart_rx   (i_uart_rx     ),
    .uart_tx   (o_uart_tx     ),
    .spi_valid (uart_spi_valid),
    .spi_cmd   (uart_spi_cmd  ),
    // UART parser only sees its own SPI completions, never boot's.
    .spi_done       (uart_busy & spi_cmd_done),
    .spi_rdata      (spi_rdata          ),
    .spi_busy       (uart_busy          ),
    .o_global_rst   (o_global_rst       ),
    .o_boot_start   (boot_start_uart    ),
    .i_boot_busy    (boot_busy          ),
    .i_boot_done    (boot_done_sticky   ),
    .i_boot_chip    (boot_chip          ),
    .i_boot_err     (boot_err           ),
    .i_si5340_lolb  (i_si5340_lolb      ),
    .i_si5340_losxb (i_si5340_losxb     ),
    .o_adc_arm      (o_adc_arm          ),
    .o_adc_n        (o_adc_n            ),
    .o_adc_rd_addr  (o_adc_rd_addr      ),
    .o_adc_chan_sel (o_adc_chan_sel     ),
    .i_adc_done     (i_adc_done         ),
    .i_adc_busy     (i_adc_busy         ),
    // New snapshot path already performs channel select internally using
    // o_adc_chan_sel, so parser consumes a single read-data port here.
    .i_adc_rdata    (i_adc_rdata),
    .o_dac_tone_en  (o_dac_tone_en      ),
    .o_dac_wave_sel (o_dac_wave_sel     ),
    .o_dac_hb_bypass(o_dac_hb_bypass    ),
    .o_dac_freq_word(o_dac_freq_word    ),
    .o_dac_amp_pct  (o_dac_amp_pct      ),
    .o_dac_dclk_ps_target(o_dac_dclk_ps_target),
    .o_nco_freq_word(o_nco_freq_word    ),
    .o_dec_ratio    (o_dec_ratio        ),
    .o_capture_mode (o_capture_mode     ),
    .o_iq_bypass    (o_iq_bypass        ),
    .o_fir_bypass   (o_fir_bypass       ),
    .o_fir_sel      (o_fir_sel          ),
    .o_iq_mult_op1  (o_iq_mult_op1      ),
    .o_iq_mult_op2  (o_iq_mult_op2      ),
    .o_iq_offset_i  (o_iq_offset_i      ),
    .o_iq_offset_q  (o_iq_offset_q      ),
    .i_stream_byte  (i_stream_byte      ),
    .i_stream_byte_vld(i_stream_byte_vld),
    .i_stream_overflow(i_stream_overflow),
    .o_stream_enable(o_stream_enable    ),
    .o_stream_byte_ready(o_stream_byte_ready),
    .o_wave_play_en         (o_wave_play_en        ),
    .o_wave_loop_len_minus1 (o_wave_loop_len_minus1),
    .o_wave_swap_iq         (o_wave_swap_iq        ),
    .o_wave_neg_q           (o_wave_neg_q          ),
    .o_wave_wr_en           (o_wave_wr_en          ),
    .o_wave_wr_addr         (o_wave_wr_addr        ),
    .o_wave_wr_data         (o_wave_wr_data        ),
    .o_state        (o_led_state        ),
    .o_frame_start  (o_led_frame_start  ),
    .o_last_chip    (o_led_last_chip    ),
    .o_last_cmd     (o_led_last_cmd     ),
    .o_last_status  (o_led_last_status  )
    );

assign o_led_spi_busy = uart_busy | boot_busy;

// Boot ROM + FSM.  boot_fsm auto-starts at rst release; 0x20 re-triggers it.
boot_rom #(.DEPTH(BOOT_ROM_DEPTH), .MEM_FILE(BOOT_MEM_FILE)) u_boot_rom (
  .clk  (clk),
  .addr (boot_rom_addr),
  .data (boot_rom_data)
);

boot_fsm #(
  .CLK_HZ    (CLK_HZ),
  .ROM_DEPTH (BOOT_ROM_DEPTH)
) u_boot_fsm (
  .clk           (clk),
  .rst_n         (rst_n),
  .i_start       (boot_start),
  .i_si5340_lolb (i_si5340_lolb),
  .o_rom_addr    (boot_rom_addr),
  .i_rom_data    (boot_rom_data),
  .o_spi_valid   (boot_spi_valid),
  .o_spi_cmd     (boot_spi_cmd),
  .i_spi_done    (boot_spi_done),
  .o_busy        (boot_busy),
  .o_done        (boot_done_pulse),
  .o_done_sticky (boot_done_sticky),
  .o_chip        (boot_chip),
  .o_err         (boot_err)
);

assign o_boot_busy = boot_busy;
assign o_boot_done = boot_done_sticky;
assign o_boot_chip = boot_chip;
assign o_boot_err  = boot_err;

// Priority mux: boot > uart > bb-bus.  boot_busy and uart_busy never overlap
// (UART parser rejects SPI cmds with status=0x05 while boot is running).
assign spi_start_mux = boot_busy ? boot_spi_valid :
                       uart_busy ? uart_spi_valid : spi_cmd_valid;
assign spi_cmd_mux   = boot_busy ? boot_spi_cmd   :
                       uart_busy ? uart_spi_cmd   : spi_cmd;

 rf_spi_core  u_rf_spi_core
(
    .clk              (clk                ),
    .rst_n            (rst_n              ),
    .soft_reset        (soft_reset),
    .spi_slv_sel          (spi_cmd_mux[62:60]     ),
    .spi_frame_size       (spi_frame_size     ),
    .spi_switch_point     (spi_rd_switch_point   ),
    .spi_data             (acp_mode ? {spi_cmd_mux[39:0], 16'h0} : spi_cmd_mux[55:0]      ),
    .spi_start            (spi_start_mux      ),
    .spi_cpol             (spi_cpol           ),
    .spi_cpha             (spi_cpha           ),
    .spi_divider          (spi_cmd_mux[56] ? {1'b0,spi_rclk_div} : {1'b0, spi_wclk_div} ),
    .spi_bidrection       (spi_bidirection     ),
    .spi_read             (spi_cmd_mux[56]           ),
    .spi_capture_delay_sel  (spi_capture_delay_sel),
    .spi_rdata             (spi_rdata          ),
    .spi_cmd_done       (spi_cmd_done       ),
    .spi0_miso0         (spi0_miso0),
    .spi1_miso0         (spi1_miso0),
    .spi2_miso0         (spi2_miso0),
    .spi3_miso0         (spi3_miso0),
    .spi4_miso0         (spi4_miso0),
    .spi5_miso0         (spi5_miso0),
    .spi7_miso0         (spi7_miso0),
    .spi0_miso1         (spi0_miso1),
    .spi1_miso1         (spi1_miso1),
    .spi2_miso1         (spi2_miso1),
    .spi3_miso1         (spi3_miso1),
    .spi4_miso1         (spi4_miso1),
    .spi5_miso1         (spi5_miso1),
    .spi7_miso1         (spi7_miso1),

    .spi0_clk           (spi0_clk  ),
    .spi1_clk           (spi1_clk  ),
    .spi2_clk           (spi2_clk  ),
    .spi3_clk           (spi3_clk  ),
    .spi4_clk           (spi4_clk  ),
    .spi5_clk           (spi5_clk  ),
    .spi7_clk           (spi7_clk  ),

    .spi0_mosi          (spi0_mosi ),
    .spi1_mosi          (spi1_mosi ),
    .spi2_mosi          (spi2_mosi ),
    .spi3_mosi          (spi3_mosi ),
    .spi4_mosi          (spi4_mosi ),
    .spi5_mosi          (spi5_mosi ),
    .spi7_mosi          (spi7_mosi ),

    .spi0_oen           (spi0_oen  ),
    .spi1_oen           (spi1_oen  ),
    .spi2_oen           (spi2_oen  ),
    .spi3_oen           (spi3_oen  ),
    .spi4_oen           (spi4_oen  ),
    .spi5_oen           (spi5_oen  ),
    .spi7_oen           (spi7_oen  ),

    .spi0_cs            (spi0_cs),
    .spi1_cs            (spi1_cs),
    .spi2_cs            (spi2_cs),
    .spi3_cs            (spi3_cs),
    .spi4_cs            (spi4_cs),
    .spi5_cs            (spi5_cs),
    .spi6_cs            (spi6_cs),
    .spi7_cs            (spi7_cs)

  );

rf_spram_mux u_rf_spram_mux
(
//globals
  .clk                (clk  ),
  .rst_n              (rst_n),
//
//config bus
  .cpu_sram_wr             (cpu_sram_wr   ),
  .cpu_sram_rd             (cpu_sram_rd   ),
  .cpu_sram_addr           (cpu_sram_addr ),
  .cpu_sram_wdata          (cpu_sram_wdata),
  .cpu_sram_rdata          (cpu_sram_rdata),

//gpo_read port
  .gposram_read_valid     (gposram_read_valid ),
  .gposram_ram_ack        (gposram_ram_ack    ),
  .gposram_read_addr      (gposram_read_addr  ),
  .gposram_rdata          (gposram_rdata      ),
  .gposram_rdata_valid    (gposram_rdata_valid),

//spi read writeport
  .spisram_read_valid     (spisram_read_valid ),
  .spisram_write_valid    (spisram_write_valid),
  .spisram_ram_ack        (spisram_ram_ack    ),
  .spisram_read_addr      (spisram_read_addr  ),
  .spisram_write_addr     (spisram_write_addr ),
  .spisram_wdata          (spisram_wdata      ),
  .spisram_rdata          (spisram_rdata      ),
  .spisram_rdata_valid    (spisram_rdata_valid),

  .spram_en           (spram_en   ),
  .spram_we           (spram_we   ),
  .spram_addr         (spram_addr ),
  .spram_wdata        (spram_wdata),
  .spram_rdata        (spram_rdata)
);

spram_512x32_w u_spram
(
  .CLK   (clk),
  .T_RWM (T_RWM),
  .CEB   (~spram_en),
  .WEB   (~spram_we),
  .BWEB  ({32{~spram_we}}),
  .A     (spram_addr),
  .D     (spram_wdata),
  .Q     (spram_rdata)
);

endmodule
