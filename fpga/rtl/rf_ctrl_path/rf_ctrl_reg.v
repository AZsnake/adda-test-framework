// Copyright (c) 2007-2012, INNOFIDEI Technologies. All Rights Reserved.
// INNOFIDEI Confidential Proprietary
// --------------------------------------------------------------------------
// FILE NAME : rf_ctrl_reg.v
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
module rf_ctrl_reg (
  //globals
      clk                  ,
      config_clk           ,
      rst_n                ,
  //
      i_gp_trigger         ,
      gpo                  ,
  //config bus
  reg_wr                   ,
  reg_rd                   ,
  reg_addr                 ,
  reg_wdata                ,
  reg_rdata                ,
  reg_rdata_vld            ,
  //output
      soft_set_gpo1        ,
      soft_gpo1            ,
      soft_set_gpo2        ,
      soft_gpo2            ,
  //
      spi_trigger_valid    ,
      spi_trigger_num      ,
      spi_trigger_cmd      ,
      spi_trigger_req      ,

      spi_trigger_done     ,
      spi_trigger_done_num ,

      gpo_trigger_valid    ,
      gpo_trigger_num      ,
      gpo_trigger_cmd      ,
      gpo_trigger_req      ,

      gpo_trigger_done     ,
      gpo_trigger_done_num ,

  //
      spi_slave_sel        ,
      spi_acp_frmsize      ,
      spi_acp_swpoint      ,
      spi_frame_size       ,
      spi_bidirection      ,
      spi_rd_switch_point  ,
      spi_cpol             ,
      spi_cpha             ,
      spi_split_interval   ,
      acp_mode             ,
      cpu_sram_wr          ,
      cpu_sram_rd          ,
      cpu_sram_addr        ,
      cpu_sram_wdata       ,
      cpu_sram_rdata       ,

      spi_iir              ,
      spi_iir_en           ,
      spi_iir_done         ,
      spi_iir_rdata        ,

      spi_batch_cmd        ,
      spi_batch_en         ,
      spi_batch_done       ,

      spi_rclk_div         ,
      spi_wclk_div         ,
      spi_capture_delay_sel,
      spi_cmd_currentstate ,
      gpo_cmd_currentstate ,
      o_et_ctrl
  );


//------------------------------------------------------------------------------
// Inputs / Outputs
//------------------------------------------------------------------------------
//globals
  input         clk                  ;
  input         config_clk           ;

  input         rst_n                ;
  input  [31:0] i_gp_trigger         ; // trigger input
  input  [61:0] gpo                  ;
//config bus
  input             reg_wr            ;
  input             reg_rd            ;
  input  [14:0] reg_addr             ;
  input  [31:0] reg_wdata            ;
  output [31:0] reg_rdata            ;
  output            reg_rdata_vld     ;

//output
  output        soft_set_gpo1        ;
  output [30:0] soft_gpo1            ;
  output        soft_set_gpo2        ;
  output [30:0] soft_gpo2            ;

//spi trigger cmd
  input         spi_trigger_valid    ;
  input   [4:0] spi_trigger_num      ;
  output [16:0] spi_trigger_cmd      ;
  output [31:0] spi_trigger_req      ;
  input         spi_trigger_done     ;
  input   [4:0] spi_trigger_done_num ;

  input         gpo_trigger_valid    ;
  input   [4:0] gpo_trigger_num      ;
  output [31:0] gpo_trigger_req      ;

  output [16:0] gpo_trigger_cmd      ;
  input         gpo_trigger_done     ;
  input   [4:0] gpo_trigger_done_num ;

//
  input   [2:0] spi_slave_sel        ;
  input   [5:0] spi_acp_frmsize      ;
  input   [4:0] spi_acp_swpoint      ;
  output  [5:0] spi_frame_size       ;
  output        spi_bidirection      ;
  output  [4:0] spi_rd_switch_point  ;
  output        spi_cpol             ;
  output        spi_cpha             ;
  output  [6:0] spi_split_interval   ;
  output        acp_mode             ;

  output        cpu_sram_wr          ;
  output        cpu_sram_rd          ;
  output  [8:0] cpu_sram_addr        ;
  output [31:0] cpu_sram_wdata       ;
  input  [31:0] cpu_sram_rdata       ;

  output [62:0] spi_iir              ;
  output        spi_iir_en           ;
  input         spi_iir_done         ;
  input  [55:0] spi_iir_rdata        ;

  output [16:0] spi_batch_cmd        ;
  output        spi_batch_en         ;
  input         spi_batch_done       ;
  output [14:0] spi_rclk_div         ;
  output [14:0] spi_wclk_div         ;
  output        spi_capture_delay_sel;
  input   [3:0] spi_cmd_currentstate ;
  input   [2:0] gpo_cmd_currentstate ;
  output [31:0] o_et_ctrl            ;
//------------------------------------------------------------------------------
//parameter define
//------------------------------------------------------------------------------
  parameter [12:0] SOFT_SET_GPO1       = 13'h0      ;
  parameter [12:0] SOFT_SET_GPO2       = 13'h1      ;
  parameter [12:0] SOFT_TRIGGER        = 13'h2      ;
  parameter [12:0] TRIGGER0_GPO_EVENT  = 13'h3      ;
  parameter [12:0] TRIGGER1_GPO_EVENT  = 13'h4      ;
  parameter [12:0] TRIGGER2_GPO_EVENT  = 13'h5      ;
  parameter [12:0] TRIGGER3_GPO_EVENT  = 13'h6      ;
  parameter [12:0] TRIGGER4_GPO_EVENT  = 13'h7      ;
  parameter [12:0] TRIGGER5_GPO_EVENT  = 13'h8      ;
  parameter [12:0] TRIGGER6_GPO_EVENT  = 13'h9      ;
  parameter [12:0] TRIGGER7_GPO_EVENT  = 13'ha      ;
  parameter [12:0] TRIGGER8_GPO_EVENT  = 13'hb      ;
  parameter [12:0] TRIGGER9_GPO_EVENT  = 13'hc      ;
  parameter [12:0] TRIGGER10_GPO_EVENT = 13'hd      ;
  parameter [12:0] TRIGGER11_GPO_EVENT = 13'he      ;
  parameter [12:0] TRIGGER12_GPO_EVENT = 13'hf      ;
  parameter [12:0] TRIGGER13_GPO_EVENT = 13'h10     ;
  parameter [12:0] TRIGGER14_GPO_EVENT = 13'h11     ;
  parameter [12:0] TRIGGER15_GPO_EVENT = 13'h12     ;
  parameter [12:0] TRIGGER16_GPO_EVENT = 13'h13     ;
  parameter [12:0] TRIGGER17_GPO_EVENT = 13'h14     ;
  parameter [12:0] TRIGGER18_GPO_EVENT = 13'h15     ;
  parameter [12:0] TRIGGER19_GPO_EVENT = 13'h16     ;
  parameter [12:0] TRIGGER20_GPO_EVENT = 13'h17     ;
  parameter [12:0] TRIGGER21_GPO_EVENT = 13'h18     ;
  parameter [12:0] TRIGGER22_GPO_EVENT = 13'h19     ;
  parameter [12:0] TRIGGER23_GPO_EVENT = 13'h1a     ;
  parameter [12:0] TRIGGER24_GPO_EVENT = 13'h1b     ;
  parameter [12:0] TRIGGER25_GPO_EVENT = 13'h1c     ;
  parameter [12:0] TRIGGER26_GPO_EVENT = 13'h1d     ;
  parameter [12:0] TRIGGER27_GPO_EVENT = 13'h1e     ;
  parameter [12:0] TRIGGER28_GPO_EVENT = 13'h1f     ;
  parameter [12:0] TRIGGER29_GPO_EVENT = 13'h20     ;
  parameter [12:0] TRIGGER30_GPO_EVENT = 13'h21     ;
  parameter [12:0] TRIGGER31_GPO_EVENT = 13'h22     ;
  parameter [12:0] TRIGGER0_SPI_EVENT  = 13'h23     ;
  parameter [12:0] TRIGGER1_SPI_EVENT  = 13'h24     ;
  parameter [12:0] TRIGGER2_SPI_EVENT  = 13'h25     ;
  parameter [12:0] TRIGGER3_SPI_EVENT  = 13'h26     ;
  parameter [12:0] TRIGGER4_SPI_EVENT  = 13'h27     ;
  parameter [12:0] TRIGGER5_SPI_EVENT  = 13'h28     ;
  parameter [12:0] TRIGGER6_SPI_EVENT  = 13'h29     ;
  parameter [12:0] TRIGGER7_SPI_EVENT  = 13'h2a     ;
  parameter [12:0] TRIGGER8_SPI_EVENT  = 13'h2b     ;
  parameter [12:0] TRIGGER9_SPI_EVENT  = 13'h2c     ;
  parameter [12:0] TRIGGER10_SPI_EVENT = 13'h2d     ;
  parameter [12:0] TRIGGER11_SPI_EVENT = 13'h2e     ;
  parameter [12:0] TRIGGER12_SPI_EVENT = 13'h2f     ;
  parameter [12:0] TRIGGER13_SPI_EVENT = 13'h30     ;
  parameter [12:0] TRIGGER14_SPI_EVENT = 13'h31     ;
  parameter [12:0] TRIGGER15_SPI_EVENT = 13'h32     ;
  parameter [12:0] TRIGGER16_SPI_EVENT = 13'h33     ;
  parameter [12:0] TRIGGER17_SPI_EVENT = 13'h34     ;
  parameter [12:0] TRIGGER18_SPI_EVENT = 13'h35     ;
  parameter [12:0] TRIGGER19_SPI_EVENT = 13'h36     ;
  parameter [12:0] TRIGGER20_SPI_EVENT = 13'h37     ;
  parameter [12:0] TRIGGER21_SPI_EVENT = 13'h38     ;
  parameter [12:0] TRIGGER22_SPI_EVENT = 13'h39     ;
  parameter [12:0] TRIGGER23_SPI_EVENT = 13'h3a     ;
  parameter [12:0] TRIGGER24_SPI_EVENT = 13'h3b     ;
  parameter [12:0] TRIGGER25_SPI_EVENT = 13'h3c     ;
  parameter [12:0] TRIGGER26_SPI_EVENT = 13'h3d     ;
  parameter [12:0] TRIGGER27_SPI_EVENT = 13'h3e     ;
  parameter [12:0] TRIGGER28_SPI_EVENT = 13'h3f     ;
  parameter [12:0] TRIGGER29_SPI_EVENT = 13'h40     ;
  parameter [12:0] TRIGGER30_SPI_EVENT = 13'h41     ;
  parameter [12:0] TRIGGER31_SPI_EVENT = 13'h42     ;
  parameter [12:0] TRIGGER_SPI_EN      = 13'h43     ;
  parameter [12:0] TRIGGER_GPO_EN      = 13'h44     ;
  parameter [12:0] TRIGGER_STATE       = 13'h45     ;
  parameter [12:0] TRIGGER_LOST        = 13'h46     ;
  parameter [12:0] SPI0_CONFIG         = 13'h47     ;
  parameter [12:0] SPI1_CONFIG         = 13'h48     ;
  parameter [12:0] SPI2_CONFIG         = 13'h49     ;
  parameter [12:0] SPI3_CONFIG         = 13'h4a     ;
  parameter [12:0] SPI4_CONFIG         = 13'h4b     ;
  parameter [12:0] SPI5_CONFIG         = 13'h4c     ;
  parameter [12:0] SPI6_CONFIG         = 13'h4d     ;
  parameter [12:0] SPI7_CONFIG         = 13'h4e     ;
  parameter [12:0] SPI_CLK_DIV         = 13'h4f     ;
  parameter [12:0] SPI_IIR1            = 13'h50     ;
  parameter [12:0] SPI_IIR2            = 13'h51     ;
  parameter [12:0] SPI_BATCH           = 13'h52     ;
  parameter [12:0] CTRLPATH_STATE      = 13'h53     ;
  parameter [12:0] ET_CTRL             = 13'h54     ;
  parameter [12:0] TRIGGER_SPI_CLR     = 13'h55     ;
  parameter [12:0] TRIGGER_GPO_CLR     = 13'h56     ;

//------------------------------------------------------------------------------
//internal signals
//------------------------------------------------------------------------------
  reg  [16:0] gpo_trigger_cmd      ;
  reg  [16:0] spi_trigger_cmd      ;
  wire [31:0] spi_trigger_req      ;
  reg         soft_set_gpo1        ;
  reg  [30:0] soft_gpo1            ;
  reg         soft_set_gpo2        ;
  reg  [30:0] soft_gpo2            ;
  reg  [62:0] spi_iir              ;
  reg         spi_iir_en           ;

  reg         acp_mode             ;
  reg   [5:0] spi_frame_size       ;
  reg         spi_bidirection      ;
  reg   [4:0] spi_rd_switch_point  ;
  reg         spi_cpol             ;
  reg         spi_cpha             ;
  reg   [6:0] spi_split_interval   ;
  reg   [7:0] acp_digrf_mode       ;
  reg   [5:0] spi0_frame_size      ;
  reg         spi0_bidirection     ;
  reg   [4:0] spi0_rd_switch_point ;
  reg         spi0_cpol            ;
  reg         spi0_cpha            ;
  reg   [6:0] spi0_split_interval  ;

  reg   [5:0] spi1_frame_size      ;
  reg         spi1_bidirection     ;
  reg   [4:0] spi1_rd_switch_point ;
  reg         spi1_cpol            ;
  reg         spi1_cpha            ;
  reg   [6:0] spi1_split_interval  ;

  reg   [5:0] spi2_frame_size      ;
  reg         spi2_bidirection     ;
  reg   [4:0] spi2_rd_switch_point ;
  reg         spi2_cpol            ;
  reg         spi2_cpha            ;
  reg   [6:0] spi2_split_interval  ;

  reg   [5:0] spi3_frame_size      ;
  reg         spi3_bidirection     ;
  reg   [4:0] spi3_rd_switch_point ;
  reg         spi3_cpol            ;
  reg         spi3_cpha            ;
  reg   [6:0] spi3_split_interval  ;

  reg   [5:0] spi4_frame_size      ;
  reg         spi4_bidirection     ;
  reg   [4:0] spi4_rd_switch_point ;
  reg         spi4_cpol            ;
  reg         spi4_cpha            ;
  reg   [6:0] spi4_split_interval  ;

  reg   [5:0] spi5_frame_size      ;
  reg         spi5_bidirection     ;
  reg   [4:0] spi5_rd_switch_point ;
  reg         spi5_cpol            ;
  reg         spi5_cpha            ;
  reg   [6:0] spi5_split_interval  ;

  reg   [5:0] spi6_frame_size      ;
  reg         spi6_bidirection     ;
  reg   [4:0] spi6_rd_switch_point ;
  reg         spi6_cpol            ;
  reg         spi6_cpha            ;
  reg   [6:0] spi6_split_interval  ;

  reg   [5:0] spi7_frame_size      ;
  reg         spi7_bidirection     ;
  reg   [4:0] spi7_rd_switch_point ;
  reg         spi7_cpol            ;
  reg         spi7_cpha            ;
  reg   [6:0] spi7_split_interval  ;

  reg  [16:0] trigger0_gpo_cmd     ;
  reg  [16:0] trigger1_gpo_cmd     ;
  reg  [16:0] trigger2_gpo_cmd     ;
  reg  [16:0] trigger3_gpo_cmd     ;
  reg  [16:0] trigger4_gpo_cmd     ;
  reg  [16:0] trigger5_gpo_cmd     ;
  reg  [16:0] trigger6_gpo_cmd     ;
  reg  [16:0] trigger7_gpo_cmd     ;
  reg  [16:0] trigger8_gpo_cmd     ;
  reg  [16:0] trigger9_gpo_cmd     ;
  reg  [16:0] trigger10_gpo_cmd    ;
  reg  [16:0] trigger11_gpo_cmd    ;
  reg  [16:0] trigger12_gpo_cmd    ;
  reg  [16:0] trigger13_gpo_cmd    ;
  reg  [16:0] trigger14_gpo_cmd    ;
  reg  [16:0] trigger15_gpo_cmd    ;
  reg  [16:0] trigger16_gpo_cmd    ;
  reg  [16:0] trigger17_gpo_cmd    ;
  reg  [16:0] trigger18_gpo_cmd    ;
  reg  [16:0] trigger19_gpo_cmd    ;
  reg  [16:0] trigger20_gpo_cmd    ;
  reg  [16:0] trigger21_gpo_cmd    ;
  reg  [16:0] trigger22_gpo_cmd    ;
  reg  [16:0] trigger23_gpo_cmd    ;
  reg  [16:0] trigger24_gpo_cmd    ;
  reg  [16:0] trigger25_gpo_cmd    ;
  reg  [16:0] trigger26_gpo_cmd    ;
  reg  [16:0] trigger27_gpo_cmd    ;
  reg  [16:0] trigger28_gpo_cmd    ;
  reg  [16:0] trigger29_gpo_cmd    ;
  reg  [16:0] trigger30_gpo_cmd    ;
  reg  [16:0] trigger31_gpo_cmd    ;

  reg  [16:0] trigger0_spi_cmd     ;
  reg  [16:0] trigger1_spi_cmd     ;
  reg  [16:0] trigger2_spi_cmd     ;
  reg  [16:0] trigger3_spi_cmd     ;
  reg  [16:0] trigger4_spi_cmd     ;
  reg  [16:0] trigger5_spi_cmd     ;
  reg  [16:0] trigger6_spi_cmd     ;
  reg  [16:0] trigger7_spi_cmd     ;
  reg  [16:0] trigger8_spi_cmd     ;
  reg  [16:0] trigger9_spi_cmd     ;
  reg  [16:0] trigger10_spi_cmd    ;
  reg  [16:0] trigger11_spi_cmd    ;
  reg  [16:0] trigger12_spi_cmd    ;
  reg  [16:0] trigger13_spi_cmd    ;
  reg  [16:0] trigger14_spi_cmd    ;
  reg  [16:0] trigger15_spi_cmd    ;
  reg  [16:0] trigger16_spi_cmd    ;
  reg  [16:0] trigger17_spi_cmd    ;
  reg  [16:0] trigger18_spi_cmd    ;
  reg  [16:0] trigger19_spi_cmd    ;
  reg  [16:0] trigger20_spi_cmd    ;
  reg  [16:0] trigger21_spi_cmd    ;
  reg  [16:0] trigger22_spi_cmd    ;
  reg  [16:0] trigger23_spi_cmd    ;
  reg  [16:0] trigger24_spi_cmd    ;
  reg  [16:0] trigger25_spi_cmd    ;
  reg  [16:0] trigger26_spi_cmd    ;
  reg  [16:0] trigger27_spi_cmd    ;
  reg  [16:0] trigger28_spi_cmd    ;
  reg  [16:0] trigger29_spi_cmd    ;
  reg  [16:0] trigger30_spi_cmd    ;
  reg  [16:0] trigger31_spi_cmd    ;

  reg  [16:0] spi_batch_cmd        ;
  reg         spi_batch_en         ;
  reg         reg_rd_d1            ;
  reg         reg_wr_d1            ;
  reg  [31:0] reg_wdata_d1         ;
  reg  [14:2] reg_addr_d1          ;
  reg         reg_rd_d2            ;
  reg  [14:2] reg_addr_d2          ;
  reg  [31:0] spi_done_value       ;
  reg  [31:0] gpo_done_value       ;
  reg  [31:0] trigger_spi_clr      ;
  reg  [31:0] trigger_gpo_clr      ;
  wire [31:0] hard_trigger         ;
  wire [31:0] spi_trigger          ;
  wire [31:0] gpo_trigger          ;
  reg  [31:0] soft_trigger         ;
  reg  [31:0] spi_trigger_reg      ;
  reg  [31:0] gpo_trigger_reg      ;
  reg  [31:0] i_gp_trigger_d1      ;
  reg  [31:0] trigger_spi_en       ;
  reg  [31:0] trigger_gpo_en       ;
  reg  [14:0] spi_rclk_div         ;
  reg  [14:0] spi_wclk_div         ;
  reg         spi_capture_delay_sel;
  reg  [31:0] reg_rdata_register   ;
  reg  [31:0] trigger_lost         ;
  reg  [31:0] o_et_ctrl            ;

//------------------------------------------------------------------------------
//beginning main code
//------------------------------------------------------------------------------
  assign cpu_sram_wr    = reg_addr[14]&reg_wr;
  assign cpu_sram_rd    = reg_addr[14]&reg_rd;
  assign cpu_sram_addr  = reg_addr[10:2]     ;
  assign cpu_sram_wdata = reg_wdata          ;
  
always @(posedge clk or negedge rst_n) begin
  if(!rst_n)
    i_gp_trigger_d1   <= #1 'h0;
  else
    i_gp_trigger_d1   <= #1 i_gp_trigger;
end

assign hard_trigger    = ~i_gp_trigger_d1&i_gp_trigger             ;
assign spi_trigger     = (hard_trigger|soft_trigger)&trigger_spi_en;
assign gpo_trigger     = (hard_trigger|soft_trigger)&trigger_gpo_en;
assign spi_trigger_req = spi_trigger_reg                           ;
assign gpo_trigger_req = gpo_trigger_reg                           ;

always@*
    begin
  spi_done_value    = 32'h0;
  if(spi_trigger_done)
      case(spi_trigger_done_num)
        5'h0   : spi_done_value = 32'h1       ;
        5'h1   : spi_done_value = 32'h2       ;
        5'h2   : spi_done_value = 32'h4       ;
        5'h3   : spi_done_value = 32'h8       ;
        5'h4   : spi_done_value = 32'h10      ;
        5'h5   : spi_done_value = 32'h20      ;
        5'h6   : spi_done_value = 32'h40      ;
        5'h7   : spi_done_value = 32'h80      ;
        5'h8   : spi_done_value = 32'h100     ;
        5'h9   : spi_done_value = 32'h200     ;
        5'ha   : spi_done_value = 32'h400     ;
        5'hb   : spi_done_value = 32'h800     ;
        5'hc   : spi_done_value = 32'h1000    ;
        5'hd   : spi_done_value = 32'h2000    ;
        5'he   : spi_done_value = 32'h4000    ;
        5'hf   : spi_done_value = 32'h8000    ;
        5'h10  : spi_done_value = 32'h10000   ;
        5'h11  : spi_done_value = 32'h20000   ;
        5'h12  : spi_done_value = 32'h40000   ;
        5'h13  : spi_done_value = 32'h80000   ;
        5'h14  : spi_done_value = 32'h100000  ;
        5'h15  : spi_done_value = 32'h200000  ;
        5'h16  : spi_done_value = 32'h400000  ;
        5'h17  : spi_done_value = 32'h800000  ;
        5'h18  : spi_done_value = 32'h1000000 ;
        5'h19  : spi_done_value = 32'h2000000 ;
        5'h1a  : spi_done_value = 32'h4000000 ;
        5'h1b  : spi_done_value = 32'h8000000 ;
        5'h1c  : spi_done_value = 32'h10000000;
        5'h1d  : spi_done_value = 32'h20000000;
        5'h1e  : spi_done_value = 32'h40000000;
        5'h1f  : spi_done_value = 32'h80000000;
        default: spi_done_value = 32'h0       ;
      endcase
  else
    spi_done_value    = 32'h0;
end

always@*
    begin
  gpo_done_value    = 32'h0;
  if(gpo_trigger_done)
      case(gpo_trigger_done_num)
        5'h0   : gpo_done_value = 32'h1       ;
        5'h1   : gpo_done_value = 32'h2       ;
        5'h2   : gpo_done_value = 32'h4       ;
        5'h3   : gpo_done_value = 32'h8       ;
        5'h4   : gpo_done_value = 32'h10      ;
        5'h5   : gpo_done_value = 32'h20      ;
        5'h6   : gpo_done_value = 32'h40      ;
        5'h7   : gpo_done_value = 32'h80      ;
        5'h8   : gpo_done_value = 32'h100     ;
        5'h9   : gpo_done_value = 32'h200     ;
        5'ha   : gpo_done_value = 32'h400     ;
        5'hb   : gpo_done_value = 32'h800     ;
        5'hc   : gpo_done_value = 32'h1000    ;
        5'hd   : gpo_done_value = 32'h2000    ;
        5'he   : gpo_done_value = 32'h4000    ;
        5'hf   : gpo_done_value = 32'h8000    ;
        5'h10  : gpo_done_value = 32'h10000   ;
        5'h11  : gpo_done_value = 32'h20000   ;
        5'h12  : gpo_done_value = 32'h40000   ;
        5'h13  : gpo_done_value = 32'h80000   ;
        5'h14  : gpo_done_value = 32'h100000  ;
        5'h15  : gpo_done_value = 32'h200000  ;
        5'h16  : gpo_done_value = 32'h400000  ;
        5'h17  : gpo_done_value = 32'h800000  ;
        5'h18  : gpo_done_value = 32'h1000000 ;
        5'h19  : gpo_done_value = 32'h2000000 ;
        5'h1a  : gpo_done_value = 32'h4000000 ;
        5'h1b  : gpo_done_value = 32'h8000000 ;
        5'h1c  : gpo_done_value = 32'h10000000;
        5'h1d  : gpo_done_value = 32'h20000000;
        5'h1e  : gpo_done_value = 32'h40000000;
        5'h1f  : gpo_done_value = 32'h80000000;
        default: gpo_done_value = 32'h0       ;
      endcase
  else
    gpo_done_value    = 32'h0;
end

genvar i;
generate
    for (i=0; i<32; i=i+1) begin
        always @(posedge clk or negedge rst_n) begin
          if ( ~rst_n ) begin
            trigger_spi_en[i] <= 1'b0;
          end else if (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER_SPI_EN ) & reg_wdata_d1[i] ) begin
            trigger_spi_en[i] <= 1'b1;
          end else if ( trigger_spi_clr[i] | spi_done_value[i] ) begin
            trigger_spi_en[i] <= 1'b0;
          end
        end

        always @(posedge clk or negedge rst_n) begin
          if ( ~rst_n ) begin
            trigger_gpo_en[i] <= 1'b0;
          end else if (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER_GPO_EN ) & reg_wdata_d1[i] ) begin
            trigger_gpo_en[i] <= 1'b1;
          end else if ( trigger_gpo_clr[i] | gpo_done_value[i] ) begin
            trigger_gpo_en[i] <= 1'b0;
          end
        end
    end
endgenerate

  always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
      spi_trigger_reg       <= #1 'h0;
    else
      spi_trigger_reg       <= #1 spi_trigger | (spi_trigger_reg&(~spi_done_value));
  end

  always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
      gpo_trigger_reg       <= #1 'h0;
    else
      gpo_trigger_reg       <= #1 gpo_trigger | (gpo_trigger_reg&(~gpo_done_value));
  end

  always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
      trigger_lost          <= #1 'h0;
    else
      trigger_lost          <= #1 (spi_trigger_reg&spi_trigger)|(gpo_trigger_reg&gpo_trigger);
  end

always @(posedge config_clk or negedge rst_n) begin
  if(!rst_n) begin
    soft_set_gpo1         <= #1 'h0;
    soft_gpo1             <= #1 'h0;
    soft_set_gpo2         <= #1 'h0;
    soft_gpo2             <= #1 'h0;
    soft_trigger          <= #1 'h0;

    trigger0_gpo_cmd      <= #1 'h0;
    trigger1_gpo_cmd      <= #1 'h0;
    trigger2_gpo_cmd      <= #1 'h0;
    trigger3_gpo_cmd      <= #1 'h0;
    trigger4_gpo_cmd      <= #1 'h0;
    trigger5_gpo_cmd      <= #1 'h0;
    trigger6_gpo_cmd      <= #1 'h0;
    trigger7_gpo_cmd      <= #1 'h0;
    trigger8_gpo_cmd      <= #1 'h0;
    trigger9_gpo_cmd      <= #1 'h0;
    trigger10_gpo_cmd     <= #1 'h0;
    trigger11_gpo_cmd     <= #1 'h0;
    trigger12_gpo_cmd     <= #1 'h0;
    trigger13_gpo_cmd     <= #1 'h0;
    trigger14_gpo_cmd     <= #1 'h0;
    trigger15_gpo_cmd     <= #1 'h0;
    trigger16_gpo_cmd     <= #1 'h0;
    trigger17_gpo_cmd     <= #1 'h0;
    trigger18_gpo_cmd     <= #1 'h0;
    trigger19_gpo_cmd     <= #1 'h0;
    trigger20_gpo_cmd     <= #1 'h0;
    trigger21_gpo_cmd     <= #1 'h0;
    trigger22_gpo_cmd     <= #1 'h0;
    trigger23_gpo_cmd     <= #1 'h0;
    trigger24_gpo_cmd     <= #1 'h0;
    trigger25_gpo_cmd     <= #1 'h0;
    trigger26_gpo_cmd     <= #1 'h0;
    trigger27_gpo_cmd     <= #1 'h0;
    trigger28_gpo_cmd     <= #1 'h0;
    trigger29_gpo_cmd     <= #1 'h0;
    trigger30_gpo_cmd     <= #1 'h0;
    trigger31_gpo_cmd     <= #1 'h0;

    trigger0_spi_cmd      <= #1 'h0;
    trigger1_spi_cmd      <= #1 'h0;
    trigger2_spi_cmd      <= #1 'h0;
    trigger3_spi_cmd      <= #1 'h0;
    trigger4_spi_cmd      <= #1 'h0;
    trigger5_spi_cmd      <= #1 'h0;
    trigger6_spi_cmd      <= #1 'h0;
    trigger7_spi_cmd      <= #1 'h0;
    trigger8_spi_cmd      <= #1 'h0;
    trigger9_spi_cmd      <= #1 'h0;
    trigger10_spi_cmd     <= #1 'h0;
    trigger11_spi_cmd     <= #1 'h0;
    trigger12_spi_cmd     <= #1 'h0;
    trigger13_spi_cmd     <= #1 'h0;
    trigger14_spi_cmd     <= #1 'h0;
    trigger15_spi_cmd     <= #1 'h0;
    trigger16_spi_cmd     <= #1 'h0;
    trigger17_spi_cmd     <= #1 'h0;
    trigger18_spi_cmd     <= #1 'h0;
    trigger19_spi_cmd     <= #1 'h0;
    trigger20_spi_cmd     <= #1 'h0;
    trigger21_spi_cmd     <= #1 'h0;
    trigger22_spi_cmd     <= #1 'h0;
    trigger23_spi_cmd     <= #1 'h0;
    trigger24_spi_cmd     <= #1 'h0;
    trigger25_spi_cmd     <= #1 'h0;
    trigger26_spi_cmd     <= #1 'h0;
    trigger27_spi_cmd     <= #1 'h0;
    trigger28_spi_cmd     <= #1 'h0;
    trigger29_spi_cmd     <= #1 'h0;
    trigger30_spi_cmd     <= #1 'h0;
    trigger31_spi_cmd     <= #1 'h0;

    //    trigger_spi_en <= #1 'h0;
    //    trigger_gpo_en <= #1 'h0;

    trigger_spi_clr       <= #1 'h0;
    trigger_gpo_clr       <= #1 'h0;

    spi0_frame_size       <= #1 'h10;
    spi0_bidirection      <= #1 1'b0;
    spi0_rd_switch_point  <= #1 'h0;
    spi0_cpol             <= #1 1'b0;
    spi0_cpha             <= #1 1'b0;
    spi0_split_interval   <= #1 'h0;
    acp_digrf_mode        <= #1 'h0;
    spi1_frame_size       <= #1 'h18;
    spi1_bidirection      <= #1 1'b1;
    spi1_rd_switch_point  <= #1 'h10;
    spi1_cpol             <= #1 1'b0;
    spi1_cpha             <= #1 1'b0;
    spi1_split_interval   <= #1 'h0;

    spi2_frame_size       <= #1 'h10;
    spi2_bidirection      <= #1 1'b1;
    spi2_rd_switch_point  <= #1 'h8;
    spi2_cpol             <= #1 1'b0;
    spi2_cpha             <= #1 1'b0;
    spi2_split_interval   <= #1 'h0;

    spi3_frame_size       <= #1 'h18;
    spi3_bidirection      <= #1 1'b0;
    spi3_rd_switch_point  <= #1 'h0;
    spi3_cpol             <= #1 1'b0;
    spi3_cpha             <= #1 1'b0;
    spi3_split_interval   <= #1 'h0;

    spi4_frame_size       <= #1 'h18;
    spi4_bidirection      <= #1 1'b0;
    spi4_rd_switch_point  <= #1 'h0;
    spi4_cpol             <= #1 1'b0;
    spi4_cpha             <= #1 1'b0;
    spi4_split_interval   <= #1 'h0;

    spi5_frame_size       <= #1 'h18;
    spi5_bidirection      <= #1 1'b0;
    spi5_rd_switch_point  <= #1 'h0;
    spi5_cpol             <= #1 1'b0;
    spi5_cpha             <= #1 1'b0;
    spi5_split_interval   <= #1 'h0;

    spi6_frame_size       <= #1 'h18;
    spi6_bidirection      <= #1 1'b0;
    spi6_rd_switch_point  <= #1 'h0;
    spi6_cpol             <= #1 1'b0;
    spi6_cpha             <= #1 1'b0;
    spi6_split_interval   <= #1 'h0;

    spi7_frame_size       <= #1 'h18;
    spi7_bidirection      <= #1 1'b0;
    spi7_rd_switch_point  <= #1 'h0;
    spi7_cpol             <= #1 1'b0;
    spi7_cpha             <= #1 1'b0;
    spi7_split_interval   <= #1 'h0;

    spi_rclk_div          <= #1 'h8;
    spi_wclk_div          <= #1 'h8;
    spi_capture_delay_sel <= #1 1'b0;
    spi_batch_cmd         <= #1 'h0;
    o_et_ctrl             <= #1 32'h8000_0001;
  end else
    begin
    soft_set_gpo1 <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SOFT_SET_GPO1      ))?reg_wdata_d1[31]:1'b0;
    soft_gpo1 <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SOFT_SET_GPO1      ))?reg_wdata_d1[30:0]:31'b0;
    soft_set_gpo2 <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SOFT_SET_GPO2      ))?reg_wdata_d1[31]:1'b0;
    soft_gpo2 <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SOFT_SET_GPO2      ))?reg_wdata_d1[30:0]:31'b0;
    soft_trigger <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SOFT_TRIGGER       ))?reg_wdata_d1[31:0]:32'b0;

    trigger0_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER0_GPO_EVENT ))?reg_wdata_d1[16:0] :trigger0_gpo_cmd;
    trigger1_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER1_GPO_EVENT ))?reg_wdata_d1[16:0] :trigger1_gpo_cmd;
    trigger2_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER2_GPO_EVENT ))?reg_wdata_d1[16:0] :trigger2_gpo_cmd;
    trigger3_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER3_GPO_EVENT ))?reg_wdata_d1[16:0] :trigger3_gpo_cmd;
    trigger4_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER4_GPO_EVENT ))?reg_wdata_d1[16:0] :trigger4_gpo_cmd;
    trigger5_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER5_GPO_EVENT ))?reg_wdata_d1[16:0] :trigger5_gpo_cmd;
    trigger6_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER6_GPO_EVENT ))?reg_wdata_d1[16:0] :trigger6_gpo_cmd;
    trigger7_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER7_GPO_EVENT ))?reg_wdata_d1[16:0] :trigger7_gpo_cmd;
    trigger8_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER8_GPO_EVENT ))?reg_wdata_d1[16:0] :trigger8_gpo_cmd;
    trigger9_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER9_GPO_EVENT ))?reg_wdata_d1[16:0] :trigger9_gpo_cmd;
    trigger10_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER10_GPO_EVENT))?reg_wdata_d1[16:0] :trigger10_gpo_cmd;
    trigger11_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER11_GPO_EVENT))?reg_wdata_d1[16:0] :trigger11_gpo_cmd;
    trigger12_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER12_GPO_EVENT))?reg_wdata_d1[16:0] :trigger12_gpo_cmd;
    trigger13_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER13_GPO_EVENT))?reg_wdata_d1[16:0] :trigger13_gpo_cmd;
    trigger14_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER14_GPO_EVENT))?reg_wdata_d1[16:0] :trigger14_gpo_cmd;
    trigger15_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER15_GPO_EVENT))?reg_wdata_d1[16:0] :trigger15_gpo_cmd;
    trigger16_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER16_GPO_EVENT))?reg_wdata_d1[16:0] :trigger16_gpo_cmd;
    trigger17_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER17_GPO_EVENT))?reg_wdata_d1[16:0] :trigger17_gpo_cmd;
    trigger18_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER18_GPO_EVENT))?reg_wdata_d1[16:0] :trigger18_gpo_cmd;
    trigger19_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER19_GPO_EVENT))?reg_wdata_d1[16:0] :trigger19_gpo_cmd;
    trigger20_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER20_GPO_EVENT))?reg_wdata_d1[16:0] :trigger20_gpo_cmd;
    trigger21_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER21_GPO_EVENT))?reg_wdata_d1[16:0] :trigger21_gpo_cmd;
    trigger22_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER22_GPO_EVENT))?reg_wdata_d1[16:0] :trigger22_gpo_cmd;
    trigger23_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER23_GPO_EVENT))?reg_wdata_d1[16:0] :trigger23_gpo_cmd;
    trigger24_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER24_GPO_EVENT))?reg_wdata_d1[16:0] :trigger24_gpo_cmd;
    trigger25_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER25_GPO_EVENT))?reg_wdata_d1[16:0] :trigger25_gpo_cmd;
    trigger26_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER26_GPO_EVENT))?reg_wdata_d1[16:0] :trigger26_gpo_cmd;
    trigger27_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER27_GPO_EVENT))?reg_wdata_d1[16:0] :trigger27_gpo_cmd;
    trigger28_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER28_GPO_EVENT))?reg_wdata_d1[16:0] :trigger28_gpo_cmd;
    trigger29_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER29_GPO_EVENT))?reg_wdata_d1[16:0] :trigger29_gpo_cmd;
    trigger30_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER30_GPO_EVENT))?reg_wdata_d1[16:0] :trigger30_gpo_cmd;
    trigger31_gpo_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER31_GPO_EVENT))?reg_wdata_d1[16:0] :trigger31_gpo_cmd;

    trigger0_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER0_SPI_EVENT ))?reg_wdata_d1[16:0] :trigger0_spi_cmd;
    trigger1_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER1_SPI_EVENT ))?reg_wdata_d1[16:0] :trigger1_spi_cmd;
    trigger2_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER2_SPI_EVENT ))?reg_wdata_d1[16:0] :trigger2_spi_cmd;
    trigger3_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER3_SPI_EVENT ))?reg_wdata_d1[16:0] :trigger3_spi_cmd;
    trigger4_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER4_SPI_EVENT ))?reg_wdata_d1[16:0] :trigger4_spi_cmd;
    trigger5_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER5_SPI_EVENT ))?reg_wdata_d1[16:0] :trigger5_spi_cmd;
    trigger6_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER6_SPI_EVENT ))?reg_wdata_d1[16:0] :trigger6_spi_cmd;
    trigger7_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER7_SPI_EVENT ))?reg_wdata_d1[16:0] :trigger7_spi_cmd;
    trigger8_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER8_SPI_EVENT ))?reg_wdata_d1[16:0] :trigger8_spi_cmd;
    trigger9_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER9_SPI_EVENT ))?reg_wdata_d1[16:0] :trigger9_spi_cmd;
    trigger10_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER10_SPI_EVENT))?reg_wdata_d1[16:0] :trigger10_spi_cmd;
    trigger11_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER11_SPI_EVENT))?reg_wdata_d1[16:0] :trigger11_spi_cmd;
    trigger12_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER12_SPI_EVENT))?reg_wdata_d1[16:0] :trigger12_spi_cmd;
    trigger13_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER13_SPI_EVENT))?reg_wdata_d1[16:0] :trigger13_spi_cmd;
    trigger14_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER14_SPI_EVENT))?reg_wdata_d1[16:0] :trigger14_spi_cmd;
    trigger15_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER15_SPI_EVENT))?reg_wdata_d1[16:0] :trigger15_spi_cmd;
    trigger16_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER16_SPI_EVENT))?reg_wdata_d1[16:0] :trigger16_spi_cmd;
    trigger17_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER17_SPI_EVENT))?reg_wdata_d1[16:0] :trigger17_spi_cmd;
    trigger18_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER18_SPI_EVENT))?reg_wdata_d1[16:0] :trigger18_spi_cmd;
    trigger19_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER19_SPI_EVENT))?reg_wdata_d1[16:0] :trigger19_spi_cmd;
    trigger20_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER20_SPI_EVENT))?reg_wdata_d1[16:0] :trigger20_spi_cmd;
    trigger21_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER21_SPI_EVENT))?reg_wdata_d1[16:0] :trigger21_spi_cmd;
    trigger22_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER22_SPI_EVENT))?reg_wdata_d1[16:0] :trigger22_spi_cmd;
    trigger23_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER23_SPI_EVENT))?reg_wdata_d1[16:0] :trigger23_spi_cmd;
    trigger24_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER24_SPI_EVENT))?reg_wdata_d1[16:0] :trigger24_spi_cmd;
    trigger25_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER25_SPI_EVENT))?reg_wdata_d1[16:0] :trigger25_spi_cmd;
    trigger26_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER26_SPI_EVENT))?reg_wdata_d1[16:0] :trigger26_spi_cmd;
    trigger27_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER27_SPI_EVENT))?reg_wdata_d1[16:0] :trigger27_spi_cmd;
    trigger28_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER28_SPI_EVENT))?reg_wdata_d1[16:0] :trigger28_spi_cmd;
    trigger29_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER29_SPI_EVENT))?reg_wdata_d1[16:0] :trigger29_spi_cmd;
    trigger30_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER30_SPI_EVENT))?reg_wdata_d1[16:0] :trigger30_spi_cmd;
    trigger31_spi_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER31_SPI_EVENT))?reg_wdata_d1[16:0] :trigger31_spi_cmd;

    //      trigger_spi_en <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER_SPI_EN     ))?reg_wdata_d1[31:0]: trigger_spi_en;
    //      trigger_gpo_en <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER_GPO_EN     ))?reg_wdata_d1[31:0]: trigger_gpo_en;
    trigger_spi_clr <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER_SPI_CLR    ))?reg_wdata_d1[31:0]: trigger_spi_clr;
    trigger_gpo_clr <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==TRIGGER_GPO_CLR    ))?reg_wdata_d1[31:0]: trigger_gpo_clr;
    spi0_frame_size <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI0_CONFIG        ))?reg_wdata_d1[5:0]   :spi0_frame_size     ;
    spi0_bidirection <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI0_CONFIG        ))?reg_wdata_d1[8]     :spi0_bidirection    ;
    acp_digrf_mode[0] <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI0_CONFIG        ))?reg_wdata_d1[9]     :acp_digrf_mode[0]    ;
    spi0_rd_switch_point <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI0_CONFIG        ))?reg_wdata_d1[16:12] :spi0_rd_switch_point;
    spi0_cpol <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI0_CONFIG        ))?reg_wdata_d1[20]    :spi0_cpol           ;
    spi0_cpha <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI0_CONFIG        ))?reg_wdata_d1[24]    :spi0_cpha           ;
    spi0_split_interval <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI0_CONFIG        ))?reg_wdata_d1[31:25] :spi0_split_interval ;
    spi1_frame_size <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI1_CONFIG        ))?reg_wdata_d1[5:0]  :spi1_frame_size     ;
    spi1_bidirection <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI1_CONFIG        ))?reg_wdata_d1[8]    :spi1_bidirection    ;
    acp_digrf_mode[1] <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI1_CONFIG        ))?reg_wdata_d1[9]     :acp_digrf_mode[1]    ;
    spi1_rd_switch_point <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI1_CONFIG        ))?reg_wdata_d1[16:12]:spi1_rd_switch_point;
    spi1_cpol <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI1_CONFIG        ))?reg_wdata_d1[20]   :spi1_cpol           ;
    spi1_cpha <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI1_CONFIG        ))?reg_wdata_d1[24]   :spi1_cpha           ;
    spi1_split_interval <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI1_CONFIG        ))?reg_wdata_d1[31:25]:spi1_split_interval ;
    spi2_frame_size <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI2_CONFIG        ))?reg_wdata_d1[5:0]  :spi2_frame_size     ;
    spi2_bidirection <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI2_CONFIG        ))?reg_wdata_d1[8]    :spi2_bidirection    ;
    acp_digrf_mode[2] <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI2_CONFIG        ))?reg_wdata_d1[9]    :acp_digrf_mode[2]    ;
    spi2_rd_switch_point <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI2_CONFIG        ))?reg_wdata_d1[16:12]:spi2_rd_switch_point;
    spi2_cpol <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI2_CONFIG        ))?reg_wdata_d1[20]   :spi2_cpol           ;
    spi2_cpha <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI2_CONFIG        ))?reg_wdata_d1[24]   :spi2_cpha           ;
    spi2_split_interval <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI2_CONFIG        ))?reg_wdata_d1[31:25]:spi2_split_interval ;
    spi3_frame_size <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI3_CONFIG        ))?reg_wdata_d1[5:0]  :spi3_frame_size     ;
    spi3_bidirection <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI3_CONFIG        ))?reg_wdata_d1[8]    :spi3_bidirection    ;
    acp_digrf_mode[3] <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI3_CONFIG        ))?reg_wdata_d1[9]    :acp_digrf_mode[3]    ;
    spi3_rd_switch_point <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI3_CONFIG        ))?reg_wdata_d1[16:12]:spi3_rd_switch_point;
    spi3_cpol <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI3_CONFIG        ))?reg_wdata_d1[20]   :spi3_cpol           ;
    spi3_cpha <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI3_CONFIG        ))?reg_wdata_d1[24]   :spi3_cpha           ;
    spi3_split_interval <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI3_CONFIG        ))?reg_wdata_d1[31:25]:spi3_split_interval ;
    spi4_frame_size <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI4_CONFIG        ))?reg_wdata_d1[5:0]  :spi4_frame_size     ;
    spi4_bidirection <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI4_CONFIG        ))?reg_wdata_d1[8]    :spi4_bidirection    ;
    acp_digrf_mode[4] <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI4_CONFIG        ))?reg_wdata_d1[9]    :acp_digrf_mode[4]    ;
    spi4_rd_switch_point <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI4_CONFIG        ))?reg_wdata_d1[16:12]:spi4_rd_switch_point;
    spi4_cpol <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI4_CONFIG        ))?reg_wdata_d1[20]   :spi4_cpol           ;
    spi4_cpha <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI4_CONFIG        ))?reg_wdata_d1[24]   :spi4_cpha           ;
    spi4_split_interval <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI4_CONFIG        ))?reg_wdata_d1[31:25]:spi4_split_interval ;
    spi5_frame_size <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI5_CONFIG        ))?reg_wdata_d1[5:0]  :spi5_frame_size     ;
    spi5_bidirection <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI5_CONFIG        ))?reg_wdata_d1[8]    :spi5_bidirection    ;
    acp_digrf_mode[5] <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI5_CONFIG        ))?reg_wdata_d1[9]    :acp_digrf_mode[5]    ;
    spi5_rd_switch_point <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI5_CONFIG        ))?reg_wdata_d1[16:12]:spi5_rd_switch_point;
    spi5_cpol <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI5_CONFIG        ))?reg_wdata_d1[20]   :spi5_cpol           ;
    spi5_cpha <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI5_CONFIG        ))?reg_wdata_d1[24]   :spi5_cpha           ;
    spi5_split_interval <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI5_CONFIG        ))?reg_wdata_d1[31:25]:spi5_split_interval ;
    spi6_frame_size <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI6_CONFIG        ))?reg_wdata_d1[5:0]  :spi6_frame_size     ;
    spi6_bidirection <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI6_CONFIG        ))?reg_wdata_d1[8]    :spi6_bidirection    ;
    acp_digrf_mode[6] <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI6_CONFIG        ))?reg_wdata_d1[9]    :acp_digrf_mode[6]    ;
    spi6_rd_switch_point <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI6_CONFIG        ))?reg_wdata_d1[16:12]:spi6_rd_switch_point;
    spi6_cpol <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI6_CONFIG        ))?reg_wdata_d1[20]   :spi6_cpol           ;
    spi6_cpha <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI6_CONFIG        ))?reg_wdata_d1[24]   :spi6_cpha           ;
    spi6_split_interval <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI6_CONFIG        ))?reg_wdata_d1[31:25]:spi6_split_interval ;
    spi7_frame_size <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI7_CONFIG        ))?reg_wdata_d1[5:0]  :spi7_frame_size     ;
    spi7_bidirection <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI7_CONFIG        ))?reg_wdata_d1[8]    :spi7_bidirection    ;
    acp_digrf_mode[7] <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI7_CONFIG        ))?reg_wdata_d1[9]    :acp_digrf_mode[7]    ;
    spi7_rd_switch_point <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI7_CONFIG        ))?reg_wdata_d1[16:12]:spi7_rd_switch_point;
    spi7_cpol <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI7_CONFIG        ))?reg_wdata_d1[20]   :spi7_cpol           ;
    spi7_cpha <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI7_CONFIG        ))?reg_wdata_d1[24]   :spi7_cpha           ;
    spi7_split_interval <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI7_CONFIG        ))?reg_wdata_d1[31:25]:spi7_split_interval ;
    spi_rclk_div <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI_CLK_DIV        ))?reg_wdata_d1[14:0] :spi_rclk_div ;
    spi_wclk_div <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI_CLK_DIV        ))?reg_wdata_d1[30:16] :spi_wclk_div ;
    spi_capture_delay_sel <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI_CLK_DIV        ))?reg_wdata_d1[31] : spi_capture_delay_sel  ;
    spi_batch_cmd <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI_BATCH          ))?reg_wdata_d1[16:0] : spi_batch_cmd;
    o_et_ctrl <= #1 (reg_wr&(reg_addr[14:2]==ET_CTRL            ))?reg_wdata[31:0] : o_et_ctrl;

  end
end

always @(posedge clk or negedge rst_n) begin
  if(!rst_n)
    spi_iir <= #1 'h0;
  else
    if(spi_iir_done)
      spi_iir[55:0] <= #1 spi_iir_rdata[55:0];
  else
    begin
    spi_iir[31:0] <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI_IIR2   ))?reg_wdata_d1[31:0] : spi_iir[31:0];
    spi_iir[62:32] <= #1 (reg_wr_d1&(reg_addr_d1[14:2]==SPI_IIR1   ))?reg_wdata_d1[30:0] : spi_iir[62:32];
  end
end

always @(posedge clk or negedge rst_n) begin
  if(!rst_n)
    spi_iir_en         <= #1 1'b0;
  else
    if(reg_wr_d1&(reg_addr_d1[14:2]==SPI_IIR1)&reg_wdata_d1[31])
      spi_iir_en         <= #1 1'b1;
  else
    if(spi_iir_done)
      spi_iir_en         <= #1 1'b0;
end

always @(posedge clk or negedge rst_n) begin
  if(!rst_n)
    spi_batch_en       <= #1 1'b0;
  else
    if(reg_wr_d1&(reg_addr_d1[14:2]==SPI_BATCH)&reg_wdata_d1[17])
      spi_batch_en       <= #1 1'b1;
  else
    if(spi_batch_done)
      spi_batch_en       <= #1 1'b0;
end

always@*
      begin
        case(spi_slave_sel)
        'h0:
        begin
          spi_frame_size = acp_digrf_mode[0] ? spi_acp_frmsize : spi0_frame_size     ;
          spi_bidirection    = spi0_bidirection    ;
          spi_rd_switch_point = acp_digrf_mode[0] ? spi_acp_swpoint : spi0_rd_switch_point;
          spi_cpol           = spi0_cpol           ;
          spi_cpha           = spi0_cpha           ;
          spi_split_interval = spi0_split_interval ;
          acp_mode           = acp_digrf_mode[0]   ;
          end
        'h1:
        begin
          spi_frame_size = acp_digrf_mode[1] ? spi_acp_frmsize : spi1_frame_size     ;
          spi_bidirection = spi1_bidirection    ;
          spi_rd_switch_point = acp_digrf_mode[1] ? spi_acp_swpoint : spi1_rd_switch_point;
          spi_cpol           = spi1_cpol           ;
          spi_cpha           = spi1_cpha           ;
          spi_split_interval = spi1_split_interval ;
          acp_mode           = acp_digrf_mode[1]   ;
          end
        'h2:
        begin
          spi_frame_size = acp_digrf_mode[2] ? spi_acp_frmsize : spi2_frame_size     ;
          spi_bidirection = spi2_bidirection    ;
          spi_rd_switch_point = acp_digrf_mode[2] ? spi_acp_swpoint : spi2_rd_switch_point;
          spi_cpol           = spi2_cpol           ;
          spi_cpha           = spi2_cpha           ;
          spi_split_interval = spi2_split_interval ;
          acp_mode           = acp_digrf_mode[2]   ;
          end
        'h3:
        begin
          spi_frame_size = acp_digrf_mode[3] ? spi_acp_frmsize : spi3_frame_size     ;
          spi_bidirection = spi3_bidirection    ;
          spi_rd_switch_point = acp_digrf_mode[3] ? spi_acp_swpoint : spi3_rd_switch_point;
          spi_cpol           = spi3_cpol           ;
          spi_cpha           = spi3_cpha           ;
          spi_split_interval = spi3_split_interval ;
          acp_mode           = acp_digrf_mode[3]   ;
          end
        'h4:
        begin
          spi_frame_size = acp_digrf_mode[4] ? spi_acp_frmsize : spi4_frame_size     ;
          spi_bidirection = spi4_bidirection    ;
          spi_rd_switch_point = acp_digrf_mode[4] ? spi_acp_swpoint : spi4_rd_switch_point;
          spi_cpol           = spi4_cpol           ;
          spi_cpha           = spi4_cpha           ;
          spi_split_interval = spi4_split_interval ;
          acp_mode           = acp_digrf_mode[4]   ;
          end
        'h5:
        begin
          spi_frame_size = acp_digrf_mode[5] ? spi_acp_frmsize : spi5_frame_size     ;
          spi_bidirection = spi5_bidirection    ;
          spi_rd_switch_point = acp_digrf_mode[5] ? spi_acp_swpoint : spi5_rd_switch_point;
          spi_cpol           = spi5_cpol           ;
          spi_cpha           = spi5_cpha           ;
          spi_split_interval = spi5_split_interval ;
          acp_mode           = acp_digrf_mode[5]   ;
          end
        'h6:
        begin
          spi_frame_size = acp_digrf_mode[6] ? spi_acp_frmsize : spi6_frame_size     ;
          spi_bidirection = spi6_bidirection    ;
          spi_rd_switch_point = acp_digrf_mode[6] ? spi_acp_swpoint : spi6_rd_switch_point;
          spi_cpol           = spi6_cpol           ;
          spi_cpha           = spi6_cpha           ;
          spi_split_interval = spi6_split_interval ;
          acp_mode           = acp_digrf_mode[6]   ;
          end
        'h7:
        begin
          spi_frame_size = acp_digrf_mode[7] ? spi_acp_frmsize : spi7_frame_size     ;
          spi_bidirection = spi7_bidirection    ;
          spi_rd_switch_point = acp_digrf_mode[7] ? spi_acp_swpoint : spi7_rd_switch_point;
          spi_cpol           = spi7_cpol           ;
          spi_cpha           = spi7_cpha           ;
          spi_split_interval = spi7_split_interval ;
          acp_mode           = acp_digrf_mode[7]   ;
          end
        default:
        begin
          spi_frame_size = acp_digrf_mode[0] ? spi_acp_frmsize : spi0_frame_size     ;
          spi_bidirection = spi0_bidirection    ;
          spi_rd_switch_point = acp_digrf_mode[0] ? spi_acp_swpoint : spi0_rd_switch_point;
          spi_cpol           = spi0_cpol           ;
          spi_cpha           = spi0_cpha           ;
          spi_split_interval = spi0_split_interval ;
          acp_mode           = acp_digrf_mode[0]   ;
          end
        endcase
end

always@*
  begin
  spi_trigger_cmd = 'h0;
  if(spi_trigger_valid)
    case(spi_trigger_num)
    'h0:
    begin
      spi_trigger_cmd = trigger0_spi_cmd       ;
      end
    'h1:
    begin
      spi_trigger_cmd = trigger1_spi_cmd       ;
      end
    'h2:
    begin
      spi_trigger_cmd = trigger2_spi_cmd       ;
      end
    'h3:
    begin
      spi_trigger_cmd = trigger3_spi_cmd       ;
      end
    'h4:
    begin
      spi_trigger_cmd = trigger4_spi_cmd       ;
      end
    'h5:
    begin
      spi_trigger_cmd = trigger5_spi_cmd       ;
      end
    'h6:
    begin
      spi_trigger_cmd = trigger6_spi_cmd       ;
      end
    'h7:
    begin
      spi_trigger_cmd = trigger7_spi_cmd       ;
      end
    'h8:
    begin
      spi_trigger_cmd = trigger8_spi_cmd       ;
      end
    'h9:
    begin
      spi_trigger_cmd = trigger9_spi_cmd       ;
      end
    'ha:
    begin
      spi_trigger_cmd = trigger10_spi_cmd       ;
      end
    'hb:
    begin
      spi_trigger_cmd = trigger11_spi_cmd       ;
      end
    'hc:
    begin
      spi_trigger_cmd = trigger12_spi_cmd       ;
      end
    'hd:
    begin
      spi_trigger_cmd = trigger13_spi_cmd       ;
      end
    'he:
    begin
      spi_trigger_cmd = trigger14_spi_cmd       ;
      end
    'hf:
    begin
      spi_trigger_cmd = trigger15_spi_cmd       ;
      end
    'h10:
    begin
      spi_trigger_cmd = trigger16_spi_cmd       ;
      end
    'h11:
    begin
      spi_trigger_cmd = trigger17_spi_cmd       ;
      end
    'h12:
    begin
      spi_trigger_cmd = trigger18_spi_cmd       ;
      end
    'h13:
    begin
      spi_trigger_cmd = trigger19_spi_cmd       ;
      end
    'h14:
    begin
      spi_trigger_cmd = trigger20_spi_cmd       ;
      end
    'h15:
    begin
      spi_trigger_cmd = trigger21_spi_cmd       ;
      end
    'h16:
    begin
      spi_trigger_cmd = trigger22_spi_cmd       ;
      end
    'h17:
    begin
      spi_trigger_cmd = trigger23_spi_cmd       ;
      end
    'h18:
    begin
      spi_trigger_cmd = trigger24_spi_cmd       ;
      end
    'h19:
    begin
      spi_trigger_cmd = trigger25_spi_cmd       ;
      end
    'h1a:
    begin
      spi_trigger_cmd = trigger26_spi_cmd       ;
      end
    'h1b:
    begin
      spi_trigger_cmd = trigger27_spi_cmd       ;
      end
    'h1c:
    begin
      spi_trigger_cmd = trigger28_spi_cmd       ;
      end
    'h1d:
    begin
      spi_trigger_cmd = trigger29_spi_cmd       ;
      end
    'h1e:
    begin
      spi_trigger_cmd = trigger30_spi_cmd       ;
      end
    'h1f:
    begin
      spi_trigger_cmd = trigger31_spi_cmd       ;
      end
    default:
    begin
      spi_trigger_cmd = trigger0_spi_cmd       ;
      end
    endcase
  else
    begin
    spi_trigger_cmd = 'h0;
  end
end

always@*
  begin
  gpo_trigger_cmd = 'h0;
  if(gpo_trigger_valid)
    case(gpo_trigger_num)
    'h0:
    begin
      gpo_trigger_cmd = trigger0_gpo_cmd       ;
      end
    'h1:
    begin
      gpo_trigger_cmd = trigger1_gpo_cmd       ;
      end
    'h2:
    begin
      gpo_trigger_cmd = trigger2_gpo_cmd       ;
      end
    'h3:
    begin
      gpo_trigger_cmd = trigger3_gpo_cmd       ;
      end
    'h4:
    begin
      gpo_trigger_cmd = trigger4_gpo_cmd       ;
      end
    'h5:
    begin
      gpo_trigger_cmd = trigger5_gpo_cmd       ;
      end
    'h6:
    begin
      gpo_trigger_cmd = trigger6_gpo_cmd       ;
      end
    'h7:
    begin
      gpo_trigger_cmd = trigger7_gpo_cmd       ;
      end
    'h8:
    begin
      gpo_trigger_cmd = trigger8_gpo_cmd       ;
      end
    'h9:
    begin
      gpo_trigger_cmd = trigger9_gpo_cmd       ;
      end
    'ha:
    begin
      gpo_trigger_cmd = trigger10_gpo_cmd       ;
      end
    'hb:
    begin
      gpo_trigger_cmd = trigger11_gpo_cmd       ;
      end
    'hc:
    begin
      gpo_trigger_cmd = trigger12_gpo_cmd       ;
      end
    'hd:
    begin
      gpo_trigger_cmd = trigger13_gpo_cmd       ;
      end
    'he:
    begin
      gpo_trigger_cmd = trigger14_gpo_cmd       ;
      end
    'hf:
    begin
      gpo_trigger_cmd = trigger15_gpo_cmd       ;
      end
    'h10:
    begin
      gpo_trigger_cmd = trigger16_gpo_cmd       ;
      end
    'h11:
    begin
      gpo_trigger_cmd = trigger17_gpo_cmd       ;
      end
    'h12:
    begin
      gpo_trigger_cmd = trigger18_gpo_cmd       ;
      end
    'h13:
    begin
      gpo_trigger_cmd = trigger19_gpo_cmd       ;
      end
    'h14:
    begin
      gpo_trigger_cmd = trigger20_gpo_cmd       ;
      end
    'h15:
    begin
      gpo_trigger_cmd = trigger21_gpo_cmd       ;
      end
    'h16:
    begin
      gpo_trigger_cmd = trigger22_gpo_cmd       ;
      end
    'h17:
    begin
      gpo_trigger_cmd = trigger23_gpo_cmd       ;
      end
    'h18:
    begin
      gpo_trigger_cmd = trigger24_gpo_cmd       ;
      end
    'h19:
    begin
      gpo_trigger_cmd = trigger25_gpo_cmd       ;
      end
    'h1a:
    begin
      gpo_trigger_cmd = trigger26_gpo_cmd       ;
      end
    'h1b:
    begin
      gpo_trigger_cmd = trigger27_gpo_cmd       ;
      end
    'h1c:
    begin
      gpo_trigger_cmd = trigger28_gpo_cmd       ;
      end
    'h1d:
    begin
      gpo_trigger_cmd = trigger29_gpo_cmd       ;
      end
    'h1e:
    begin
      gpo_trigger_cmd = trigger30_gpo_cmd       ;
      end
    'h1f:
    begin
      gpo_trigger_cmd = trigger31_gpo_cmd       ;
      end
    default:
    begin
      gpo_trigger_cmd = trigger0_gpo_cmd       ;
      end
    endcase
  else
    begin
    gpo_trigger_cmd = 'h0;
  end
end

always@(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    reg_rd_d1    <= #1 1'b0;
    reg_rd_d2    <= #1 1'b0;
    reg_wr_d1    <= #1 1'b0;
    reg_wdata_d1 <= #1 'b0;
    reg_addr_d1[14:2] <= #1 14'h0;
    reg_addr_d2[14:2] <= #1 14'h0;
  end else
    begin
    reg_rd_d1    <= #1 reg_rd;
    reg_rd_d2    <= #1 reg_rd_d1;
    reg_wr_d1    <= #1 reg_wr;
    reg_wdata_d1 <= #1 reg_wdata;
    reg_addr_d1[14:2] <= #1 reg_addr[14:2];
    reg_addr_d2[14:2] <= #1 reg_addr_d1[14:2];
  end
end

always@(posedge clk or negedge rst_n) begin
  if(!rst_n)
    reg_rdata_register <= #1 'h0;
  else
    if(reg_rd_d1)
  case(reg_addr_d1[13:2])
  SPI0_CONFIG         :
  begin
    reg_rdata_register[5:0] <= #1 spi0_frame_size;
    reg_rdata_register[8] <= #1 spi0_bidirection          ;
    reg_rdata_register[9] <= #1 acp_digrf_mode[0]         ;
    reg_rdata_register[16:12] <= #1 spi0_rd_switch_point      ;
    reg_rdata_register[20] <= #1 spi0_cpol                 ;
    reg_rdata_register[24] <= #1 spi0_cpha                 ;
    reg_rdata_register[31:25] <= #1 spi0_split_interval       ;
    end
  SPI1_CONFIG         :
  begin
    reg_rdata_register[5:0] <= #1 spi1_frame_size;
    reg_rdata_register[8] <= #1 spi1_bidirection          ;
    reg_rdata_register[9] <= #1 acp_digrf_mode[1]         ;
    reg_rdata_register[16:12] <= #1 spi1_rd_switch_point      ;
    reg_rdata_register[20] <= #1 spi1_cpol                 ;
    reg_rdata_register[24] <= #1 spi1_cpha                 ;
    reg_rdata_register[31:25] <= #1 spi1_split_interval       ;
    end
  SPI2_CONFIG         :
  begin
    reg_rdata_register[5:0] <= #1 spi2_frame_size;
    reg_rdata_register[8] <= #1 spi2_bidirection          ;
    reg_rdata_register[9] <= #1 acp_digrf_mode[2]         ;
    reg_rdata_register[16:12] <= #1 spi2_rd_switch_point      ;
    reg_rdata_register[20] <= #1 spi2_cpol                 ;
    reg_rdata_register[24] <= #1 spi2_cpha                 ;
    reg_rdata_register[31:25] <= #1 spi2_split_interval       ;
    end
  SPI3_CONFIG         :
  begin
    reg_rdata_register[5:0] <= #1 spi3_frame_size;
    reg_rdata_register[8] <= #1 spi3_bidirection          ;
    reg_rdata_register[9] <= #1 acp_digrf_mode[3]         ;
    reg_rdata_register[16:12] <= #1 spi3_rd_switch_point      ;
    reg_rdata_register[20] <= #1 spi3_cpol                 ;
    reg_rdata_register[24] <= #1 spi3_cpha                 ;
    reg_rdata_register[31:25] <= #1 spi3_split_interval       ;
    end
  SPI4_CONFIG         :
  begin
    reg_rdata_register[5:0] <= #1 spi4_frame_size;
    reg_rdata_register[8] <= #1 spi4_bidirection          ;
    reg_rdata_register[9] <= #1 acp_digrf_mode[4]         ;
    reg_rdata_register[16:12] <= #1 spi4_rd_switch_point      ;
    reg_rdata_register[20] <= #1 spi4_cpol                 ;
    reg_rdata_register[24] <= #1 spi4_cpha                 ;
    reg_rdata_register[31:25] <= #1 spi4_split_interval       ;
    end
  SPI5_CONFIG         :
  begin
    reg_rdata_register[5:0] <= #1 spi5_frame_size;
    reg_rdata_register[8] <= #1 spi5_bidirection          ;
    reg_rdata_register[9] <= #1 acp_digrf_mode[5]         ;
    reg_rdata_register[16:12] <= #1 spi5_rd_switch_point      ;
    reg_rdata_register[20] <= #1 spi5_cpol                 ;
    reg_rdata_register[24] <= #1 spi5_cpha                 ;
    reg_rdata_register[31:25] <= #1 spi5_split_interval       ;
    end
  SPI6_CONFIG         :
  begin
    reg_rdata_register[5:0] <= #1 spi6_frame_size;
    reg_rdata_register[8] <= #1 spi6_bidirection          ;
    reg_rdata_register[9] <= #1 acp_digrf_mode[6]         ;
    reg_rdata_register[16:12] <= #1 spi6_rd_switch_point      ;
    reg_rdata_register[20] <= #1 spi6_cpol                 ;
    reg_rdata_register[24] <= #1 spi6_cpha                 ;
    reg_rdata_register[31:25] <= #1 spi6_split_interval       ;
    end
  SPI7_CONFIG         :
  begin
    reg_rdata_register[5:0] <= #1 spi7_frame_size;
    reg_rdata_register[8] <= #1 spi7_bidirection          ;
    reg_rdata_register[9] <= #1 acp_digrf_mode[7]         ;
    reg_rdata_register[16:12] <= #1 spi7_rd_switch_point      ;
    reg_rdata_register[20] <= #1 spi7_cpol                 ;
    reg_rdata_register[24] <= #1 spi7_cpha                 ;
    reg_rdata_register[31:25] <= #1 spi7_split_interval       ;
    end
  SOFT_SET_GPO1      : reg_rdata_register <= #1 {1'b0,gpo[30:0]}                                      ;
  SOFT_SET_GPO2      : reg_rdata_register <= #1 {1'b0,gpo[61:31]}                                     ;
    SOFT_TRIGGER       : reg_rdata_register <= #1 soft_trigger                                          ;
    TRIGGER0_GPO_EVENT : reg_rdata_register <= #1 trigger0_gpo_cmd                                      ;
    TRIGGER1_GPO_EVENT : reg_rdata_register <= #1 trigger1_gpo_cmd                                      ;
    TRIGGER2_GPO_EVENT : reg_rdata_register <= #1 trigger2_gpo_cmd                                      ;
    TRIGGER3_GPO_EVENT : reg_rdata_register <= #1 trigger3_gpo_cmd                                      ;
    TRIGGER4_GPO_EVENT : reg_rdata_register <= #1 trigger4_gpo_cmd                                      ;
    TRIGGER5_GPO_EVENT : reg_rdata_register <= #1 trigger5_gpo_cmd                                      ;
    TRIGGER6_GPO_EVENT : reg_rdata_register <= #1 trigger6_gpo_cmd                                      ;
    TRIGGER7_GPO_EVENT : reg_rdata_register <= #1 trigger7_gpo_cmd                                      ;
    TRIGGER8_GPO_EVENT : reg_rdata_register <= #1 trigger8_gpo_cmd                                      ;
    TRIGGER9_GPO_EVENT : reg_rdata_register <= #1 trigger9_gpo_cmd                                      ;
    TRIGGER10_GPO_EVENT: reg_rdata_register <= #1 trigger10_gpo_cmd                                     ;
    TRIGGER11_GPO_EVENT: reg_rdata_register <= #1 trigger11_gpo_cmd                                     ;
    TRIGGER12_GPO_EVENT: reg_rdata_register <= #1 trigger12_gpo_cmd                                     ;
    TRIGGER13_GPO_EVENT: reg_rdata_register <= #1 trigger13_gpo_cmd                                     ;
    TRIGGER14_GPO_EVENT: reg_rdata_register <= #1 trigger14_gpo_cmd                                     ;
    TRIGGER15_GPO_EVENT: reg_rdata_register <= #1 trigger15_gpo_cmd                                     ;
    TRIGGER16_GPO_EVENT: reg_rdata_register <= #1 trigger16_gpo_cmd                                     ;
    TRIGGER17_GPO_EVENT: reg_rdata_register <= #1 trigger17_gpo_cmd                                     ;
    TRIGGER18_GPO_EVENT: reg_rdata_register <= #1 trigger18_gpo_cmd                                     ;
    TRIGGER19_GPO_EVENT: reg_rdata_register <= #1 trigger19_gpo_cmd                                     ;
    TRIGGER20_GPO_EVENT: reg_rdata_register <= #1 trigger20_gpo_cmd                                     ;
    TRIGGER21_GPO_EVENT: reg_rdata_register <= #1 trigger21_gpo_cmd                                     ;
    TRIGGER22_GPO_EVENT: reg_rdata_register <= #1 trigger22_gpo_cmd                                     ;
    TRIGGER23_GPO_EVENT: reg_rdata_register <= #1 trigger23_gpo_cmd                                     ;
    TRIGGER24_GPO_EVENT: reg_rdata_register <= #1 trigger24_gpo_cmd                                     ;
    TRIGGER25_GPO_EVENT: reg_rdata_register <= #1 trigger25_gpo_cmd                                     ;
    TRIGGER26_GPO_EVENT: reg_rdata_register <= #1 trigger26_gpo_cmd                                     ;
    TRIGGER27_GPO_EVENT: reg_rdata_register <= #1 trigger27_gpo_cmd                                     ;
    TRIGGER28_GPO_EVENT: reg_rdata_register <= #1 trigger28_gpo_cmd                                     ;
    TRIGGER29_GPO_EVENT: reg_rdata_register <= #1 trigger29_gpo_cmd                                     ;
    TRIGGER30_GPO_EVENT: reg_rdata_register <= #1 trigger30_gpo_cmd                                     ;
    TRIGGER31_GPO_EVENT: reg_rdata_register <= #1 trigger31_gpo_cmd                                     ;
    TRIGGER0_SPI_EVENT : reg_rdata_register <= #1 trigger0_spi_cmd                                      ;
    TRIGGER1_SPI_EVENT : reg_rdata_register <= #1 trigger1_spi_cmd                                      ;
    TRIGGER2_SPI_EVENT : reg_rdata_register <= #1 trigger2_spi_cmd                                      ;
    TRIGGER3_SPI_EVENT : reg_rdata_register <= #1 trigger3_spi_cmd                                      ;
    TRIGGER4_SPI_EVENT : reg_rdata_register <= #1 trigger4_spi_cmd                                      ;
    TRIGGER5_SPI_EVENT : reg_rdata_register <= #1 trigger5_spi_cmd                                      ;
    TRIGGER6_SPI_EVENT : reg_rdata_register <= #1 trigger6_spi_cmd                                      ;
    TRIGGER7_SPI_EVENT : reg_rdata_register <= #1 trigger7_spi_cmd                                      ;
    TRIGGER8_SPI_EVENT : reg_rdata_register <= #1 trigger8_spi_cmd                                      ;
    TRIGGER9_SPI_EVENT : reg_rdata_register <= #1 trigger9_spi_cmd                                      ;
    TRIGGER10_SPI_EVENT: reg_rdata_register <= #1 trigger10_spi_cmd                                     ;
    TRIGGER11_SPI_EVENT: reg_rdata_register <= #1 trigger11_spi_cmd                                     ;
    TRIGGER12_SPI_EVENT: reg_rdata_register <= #1 trigger12_spi_cmd                                     ;
    TRIGGER13_SPI_EVENT: reg_rdata_register <= #1 trigger13_spi_cmd                                     ;
    TRIGGER14_SPI_EVENT: reg_rdata_register <= #1 trigger14_spi_cmd                                     ;
    TRIGGER15_SPI_EVENT: reg_rdata_register <= #1 trigger15_spi_cmd                                     ;
    TRIGGER16_SPI_EVENT: reg_rdata_register <= #1 trigger16_spi_cmd                                     ;
    TRIGGER17_SPI_EVENT: reg_rdata_register <= #1 trigger17_spi_cmd                                     ;
    TRIGGER18_SPI_EVENT: reg_rdata_register <= #1 trigger18_spi_cmd                                     ;
    TRIGGER19_SPI_EVENT: reg_rdata_register <= #1 trigger19_spi_cmd                                     ;
    TRIGGER20_SPI_EVENT: reg_rdata_register <= #1 trigger20_spi_cmd                                     ;
    TRIGGER21_SPI_EVENT: reg_rdata_register <= #1 trigger21_spi_cmd                                     ;
    TRIGGER22_SPI_EVENT: reg_rdata_register <= #1 trigger22_spi_cmd                                     ;
    TRIGGER23_SPI_EVENT: reg_rdata_register <= #1 trigger23_spi_cmd                                     ;
    TRIGGER24_SPI_EVENT: reg_rdata_register <= #1 trigger24_spi_cmd                                     ;
    TRIGGER25_SPI_EVENT: reg_rdata_register <= #1 trigger25_spi_cmd                                     ;
    TRIGGER26_SPI_EVENT: reg_rdata_register <= #1 trigger26_spi_cmd                                     ;
    TRIGGER27_SPI_EVENT: reg_rdata_register <= #1 trigger27_spi_cmd                                     ;
    TRIGGER28_SPI_EVENT: reg_rdata_register <= #1 trigger28_spi_cmd                                     ;
    TRIGGER29_SPI_EVENT: reg_rdata_register <= #1 trigger29_spi_cmd                                     ;
    TRIGGER30_SPI_EVENT: reg_rdata_register <= #1 trigger30_spi_cmd                                     ;
    TRIGGER31_SPI_EVENT: reg_rdata_register <= #1 trigger31_spi_cmd                                     ;
    TRIGGER_SPI_EN     : reg_rdata_register <= #1 trigger_spi_en                                        ;
    TRIGGER_GPO_EN     : reg_rdata_register <= #1 trigger_gpo_en                                        ;
    TRIGGER_SPI_CLR    : reg_rdata_register <= #1 trigger_spi_clr                                       ;
    TRIGGER_GPO_CLR    : reg_rdata_register <= #1 trigger_gpo_clr                                       ;
    TRIGGER_STATE      : reg_rdata_register <= #1 spi_trigger_reg|gpo_trigger_reg                       ;
    TRIGGER_LOST       : reg_rdata_register <= #1 trigger_lost                                          ;
    SPI_CLK_DIV        : reg_rdata_register <= #1 {spi_capture_delay_sel,spi_wclk_div,1'b0,spi_rclk_div};
  SPI_IIR2           : reg_rdata_register <= #1 spi_iir[31:0]                                         ;
  SPI_IIR1           : reg_rdata_register <= #1 {spi_iir_en,spi_iir[62:32]}                           ;
    SPI_BATCH          : reg_rdata_register <= #1 {14'b0,spi_batch_en,spi_batch_cmd}                    ;
    CTRLPATH_STATE     : reg_rdata_register <= #1 {25'b0,gpo_cmd_currentstate,spi_cmd_currentstate}     ;
    ET_CTRL            : reg_rdata_register <= #1 o_et_ctrl                                             ;
    default            : reg_rdata_register <= #1 'h0                                                   ;
  endcase
end

assign reg_rdata     = reg_addr_d2[14]? cpu_sram_rdata: reg_rdata_register;

assign reg_rdata_vld = reg_rd_d2                                          ;

endmodule
