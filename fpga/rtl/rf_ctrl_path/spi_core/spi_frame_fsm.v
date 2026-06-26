// Copyright (c) 2007-2012, INNOFIDEI Technologies. All Rights Reserved.
// INNOFIDEI Confidential Proprietary
// --------------------------------------------------------------------------
// FILE NAME : spi_frame_fsm.v
// AUTHOR    : zhaopeng
// -----------------------------------------------------------------------------
// RELEASE HISTORY
// VERSION    DATE          AUTHOR            DESCRIPTION
// 1.0       2012-2-03      zhaopeng
// -----------------------------------------------------------------------------
// PURPOSE : SPI function controller
// -----------------------------------------------------------------------------
// Clock Domains :
// Other :
// -FHDR------------------------------------------------------------------------
//------------------------------------------------------------------------------
// Module Declaration
//------------------------------------------------------------------------------
module spi_frame_fsm (
  clk                  ,
  rst_n                ,
  soft_reset           ,
  spi_start            ,
  spi_slv_sel          ,
  spi_cpol             ,
  spi_cpha             ,
  spi_frame_size       ,
  spi_switch_point     ,
  pos_edge             ,
  neg_edge             ,
  spi_bidrection       ,
  spi_read             ,
  spi_capture_delay_sel,

  spi0_oen             ,
  spi1_oen             ,
  spi2_oen             ,
  spi3_oen             ,
  spi4_oen             ,
  spi5_oen             ,
  spi7_oen             ,

  spi0_cs              ,
  spi1_cs              ,
  spi2_cs              ,
  spi3_cs              ,
  spi4_cs              ,
  spi5_cs              ,
  spi6_cs              ,
  spi7_cs              ,

  clkgen_en            ,
  spi_clk_en           ,
  tx_shift             ,
  rx_shift             ,
  trans_done
  );

//------------------------------------------------------------------------------
// Inputs / Outputs
//------------------------------------------------------------------------------
  input        clk                  ;
  input        rst_n                ;
  input        soft_reset           ;

  input        spi_start            ;
  input  [2:0] spi_slv_sel          ;
  input        spi_cpol             ;
  input        spi_cpha             ;
  input  [5:0] spi_frame_size       ;
  input  [4:0] spi_switch_point     ;
  input        pos_edge             ;
  input        neg_edge             ;
  input        spi_bidrection       ;
  input        spi_read             ;
  input        spi_capture_delay_sel;

  output       spi0_oen             ;
  output       spi1_oen             ;
  output       spi2_oen             ;
  output       spi3_oen             ;
  output       spi4_oen             ;
  output       spi5_oen             ;
  output       spi7_oen             ;

  output       spi0_cs              ;
  output       spi1_cs              ;
  output       spi2_cs              ;
  output       spi3_cs              ;
  output       spi4_cs              ;
  output       spi5_cs              ;
  output       spi6_cs              ;
  output       spi7_cs              ;

  output       clkgen_en            ;
  output       spi_clk_en           ;

  output       tx_shift             ;
  output       rx_shift             ;
  output       trans_done           ;

//------------------------------------------------------------------------------
// parameter define
//------------------------------------------------------------------------------
  parameter [2:0] FSM_IDLE     = 3'b000;
  parameter [2:0] FSM_SEND_CS  = 3'b001;
  parameter [2:0] FSM_SEND_CLK = 3'b011;
  parameter [2:0] FSM_LAUNCH   = 3'b010;
  parameter [2:0] FSM_CAPTURE  = 3'b110;
  parameter [2:0] FSM_STOP_CLK = 3'b111;
  parameter [2:0] FSM_STOP_CS  = 3'b101;
  parameter [2:0] FSM_END      = 3'b100;

//------------------------------------------------------------------------------
//internal signals
//------------------------------------------------------------------------------
  wire       assert_cs    ;
  wire       deassert_cs  ;
  wire       assert_sclk  ;
  wire       deassert_sclk;
  reg  [2:0] currentstate ;
  reg  [2:0] nextstate    ;
  reg  [5:0] bit_cnt      ;
  wire [5:0] bit_cnt_nxt  ;
  wire       bit_cnt_clr  ;
  wire       switch_point ;
  reg        spi_en_d1    ;
  wire [1:0] spi_mode     ;
  wire       rx_shift_pre ;
  reg        rx_shift_d1  ;
  reg        spi0_oen     ;
  reg        spi1_oen     ;
  reg        spi2_oen     ;
  reg        spi3_oen     ;
  reg        spi4_oen     ;
  reg        spi5_oen     ;
  reg        spi7_oen     ;
  reg        spi0_cs_reg  ;
  reg        spi1_cs_reg  ;
  reg        spi2_cs_reg  ;
  reg        spi3_cs_reg  ;
  reg        spi4_cs_reg  ;
  reg        spi5_cs_reg  ;
  reg        spi6_cs_reg  ;
  reg        spi7_cs_reg  ;
  reg        clkgen_en    ;
  reg        spi_clk_en   ;

//------------------------------------------------------------------------------
//beginning main code
//------------------------------------------------------------------------------
  assign bit_cnt_nxt = bit_cnt + 1'b1;
  always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0)
      bit_cnt  <= #1 6'd0;
    else
      if(soft_reset)
        bit_cnt  <= #1 6'd0;
    else
      if (bit_cnt_clr)
        bit_cnt  <= #1 6'd0;
    else if (rx_shift)
      bit_cnt  <= #1 bit_cnt_nxt;
  end

//  assign switch_point = (bit_cnt_nxt == {1'b0,spi_switch_point}) & rx_shift & spi_read & spi_bidrection;
  assign switch_point = (bit_cnt == {1'b0,spi_switch_point}) & tx_shift & spi_read & spi_bidrection;
  
always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    spi0_oen <= #1 1'b0;
    spi1_oen <= #1 1'b0;
    spi2_oen <= #1 1'b0;
    spi3_oen <= #1 1'b0;
    spi4_oen <= #1 1'b0;
    spi5_oen <= #1 1'b0;
    spi7_oen <= #1 1'b0;
  end else
    //    if(switch_point)
  if(switch_point | spi_start & (spi_switch_point == 5'b0 & spi_read & spi_bidrection ) ) begin
    spi0_oen <= #1 (spi_slv_sel == 'h0);
    spi1_oen <= #1 (spi_slv_sel == 'h1);
    spi2_oen <= #1 (spi_slv_sel == 'h2)|(spi_slv_sel == 'h6);
    spi3_oen <= #1 (spi_slv_sel == 'h3);
    spi4_oen <= #1 (spi_slv_sel == 'h4);
    spi5_oen <= #1 (spi_slv_sel == 'h5);
    spi7_oen <= #1 (spi_slv_sel == 'h7);
  end else
    if(currentstate == FSM_STOP_CS) begin
    spi0_oen <= #1 1'b0;
    spi1_oen <= #1 1'b0;
    spi2_oen <= #1 1'b0;
    spi3_oen <= #1 1'b0;
    spi4_oen <= #1 1'b0;
    spi5_oen <= #1 1'b0;
    spi7_oen <= #1 1'b0;
  end
end

always @(posedge clk or negedge rst_n) begin
  if (rst_n == 1'b0) begin
    spi0_cs_reg <= #1 1'b1;
    spi1_cs_reg <= #1 1'b1;
    spi2_cs_reg <= #1 1'b1;
    spi3_cs_reg <= #1 1'b1;
    spi4_cs_reg <= #1 1'b1;
    spi5_cs_reg <= #1 1'b1;
    spi6_cs_reg <= #1 1'b1;
    spi7_cs_reg <= #1 1'b1;
  end else
    if(assert_cs) begin
    spi0_cs_reg <= #1 !(spi_slv_sel==3'h0);
    spi1_cs_reg <= #1 !(spi_slv_sel==3'h1);
    spi2_cs_reg <= #1 !(spi_slv_sel==3'h2);
    spi3_cs_reg <= #1 !(spi_slv_sel==3'h3);
    spi4_cs_reg <= #1 !(spi_slv_sel==3'h4);
    spi5_cs_reg <= #1 !(spi_slv_sel==3'h5);
    spi6_cs_reg <= #1 !(spi_slv_sel==3'h6);
    spi7_cs_reg <= #1 !(spi_slv_sel==3'h7);
  end else
    if(deassert_cs) begin
    spi0_cs_reg <= #1 1'b1;
    spi1_cs_reg <= #1 1'b1;
    spi2_cs_reg <= #1 1'b1;
    spi3_cs_reg <= #1 1'b1;
    spi4_cs_reg <= #1 1'b1;
    spi5_cs_reg <= #1 1'b1;
    spi6_cs_reg <= #1 1'b1;
    spi7_cs_reg <= #1 1'b1;
  end
end

assign spi0_cs = spi0_cs_reg;
assign spi1_cs = spi1_cs_reg;
assign spi2_cs = spi2_cs_reg;
assign spi3_cs = spi3_cs_reg;
assign spi4_cs = spi4_cs_reg;
assign spi5_cs = spi5_cs_reg;
assign spi6_cs = spi6_cs_reg;
assign spi7_cs = spi7_cs_reg;

always @(negedge clk or negedge rst_n) begin
  if (~rst_n)
    clkgen_en    <= #1 1'b0;
  else
    if(soft_reset)
      clkgen_en    <= #1 1'b0;
  else
    if((currentstate==FSM_IDLE)&spi_start)
      clkgen_en    <= #1 1'b1;
  else
    if(currentstate==FSM_END)
      clkgen_en    <= #1 1'b0;
end

always @(negedge clk or negedge rst_n) begin
  if (~rst_n)
    spi_clk_en   <= #1 1'b0;
  else if (assert_sclk)
    spi_clk_en   <= #1 1'b1;
  else if (deassert_sclk)
    spi_clk_en   <= #1 1'b0;
end

  //fsm cs assignment
always @(posedge clk or negedge rst_n) begin
  if (~rst_n)
    currentstate <= #1 FSM_IDLE;
  else
    if(soft_reset)
      currentstate <= #1 FSM_IDLE;
  else
    currentstate <= #1 nextstate;
end

assign spi_mode = {spi_cpha, spi_cpol};

always@*
    begin
      case (currentstate)
      FSM_IDLE      :
      begin
        if(spi_start)
        nextstate = FSM_SEND_CS;
        else
        nextstate = FSM_IDLE;
        end
      FSM_SEND_CS   :
      begin
        if((pos_edge&!spi_cpol)|(neg_edge&spi_cpol))
        nextstate = FSM_SEND_CLK;
        else
        nextstate = FSM_SEND_CS;
        end
        FSM_SEND_CLK  :   //send first clk
      begin
        if(spi_cpha)
        if((neg_edge&!spi_cpol)|(pos_edge&spi_cpol))
        nextstate = FSM_CAPTURE;
        else
        nextstate = FSM_SEND_CLK;
        else
        if((neg_edge&!spi_cpol)|(pos_edge&spi_cpol))
        nextstate = FSM_LAUNCH;
        else
        nextstate = FSM_SEND_CLK;
        end
        FSM_LAUNCH    : begin
          if((pos_edge&((spi_mode == 2'b0) | (spi_mode == 2'b11)))|
          (neg_edge&((spi_mode == 2'b10) | (spi_mode == 2'b01))))
          nextstate = FSM_CAPTURE;
          else
          nextstate = FSM_LAUNCH;
        end
        FSM_CAPTURE   : begin
          if((neg_edge&((spi_mode == 2'b0) | (spi_mode == 2'b11)))|
          (pos_edge&((spi_mode == 2'b10) | (spi_mode == 2'b01))))
          if(bit_cnt== spi_frame_size)
          nextstate = FSM_STOP_CLK;
          else
          nextstate = FSM_LAUNCH;
          else
          nextstate = FSM_CAPTURE;
        end
        FSM_STOP_CLK  : begin
          if((pos_edge&((spi_mode == 2'b0) | (spi_mode == 2'b11)))|
          (neg_edge&((spi_mode == 2'b10) | (spi_mode == 2'b01))))
          nextstate = FSM_STOP_CS;
          else
          nextstate = FSM_STOP_CLK;
        end
      FSM_STOP_CS   :
      nextstate = FSM_END;
      FSM_END       :
      nextstate = FSM_IDLE;
      endcase
end

assign rx_shift_pre = ((currentstate != FSM_CAPTURE)&(nextstate == FSM_CAPTURE))|
                       ((currentstate != FSM_SEND_CLK)&(nextstate == FSM_SEND_CLK)&!spi_cpha);

always@(posedge clk or negedge rst_n) begin
  if(!rst_n)
    rx_shift_d1 <= #1 1'b0;
  else
    rx_shift_d1 <= #1 rx_shift_pre;
end

assign rx_shift      = spi_capture_delay_sel?rx_shift_d1: rx_shift_pre                         ;

assign tx_shift      = ((currentstate != FSM_LAUNCH)&(nextstate == FSM_LAUNCH))                ;
assign trans_done    = (currentstate == FSM_END)                                               ;
assign bit_cnt_clr   = (currentstate == FSM_END)                                               ;
assign assert_cs     = (currentstate == FSM_IDLE)&(nextstate == FSM_SEND_CS)                   ;
assign deassert_cs   = (currentstate == FSM_STOP_CLK)&(nextstate ==FSM_STOP_CS )               ;
assign assert_sclk   = (currentstate == FSM_SEND_CS)&(nextstate == FSM_SEND_CLK)               ;
assign deassert_sclk = ((((currentstate == FSM_CAPTURE)&(nextstate == FSM_STOP_CLK))&spi_cpha)|
                        ((currentstate == FSM_STOP_CLK)&!spi_cpha)|(currentstate == FSM_END));

endmodule
