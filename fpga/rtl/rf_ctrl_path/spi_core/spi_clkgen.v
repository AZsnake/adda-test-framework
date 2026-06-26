// Copyright (c) 2007-2012, INNOFIDEI Technologies. All Rights Reserved.
// INNOFIDEI Confidential Proprietary
// --------------------------------------------------------------------------
// FILE NAME : spi_clkgen.v
// AUTHOR :GaoBin
// AUTHOR'S EMAIL :
// -----------------------------------------------------------------------------
// RELEASE HISTORY
// VERSION    DATE          AUTHOR            DESCRIPTION
// 1.0        2010-12-03     gaobin            initial
// -----------------------------------------------------------------------------
// PURPOSE : spi clock generation
// -----------------------------------------------------------------------------
// Clock Domains :
// Other :
// -FHDR------------------------------------------------------------------------
//------------------------------------------------------------------------------
// Module Declaration
//------------------------------------------------------------------------------
module spi_clkgen (
  clk        ,
  rst_n      ,
  soft_reset ,
  spi_slv_sel,
  clkgen_en  ,
  spi_clk_en ,
  spi_cpol   ,
  spi_divider,
  spi0_clk   ,
  spi1_clk   ,
  spi2_clk   ,
  spi3_clk   ,
  spi4_clk   ,
  spi5_clk   ,
  spi7_clk   ,
  pos_edge   ,
  neg_edge
  );


//------------------------------------------------------------------------------
// Inputs / Outputs
//------------------------------------------------------------------------------
  input         clk        ;
  input         rst_n      ;
  input         soft_reset ;
  input   [2:0] spi_slv_sel;

  input         spi_clk_en ;
  input         clkgen_en  ;
  input         spi_cpol   ;
  input  [15:0] spi_divider;
  output        spi0_clk   ;
  output        spi1_clk   ;
  output        spi2_clk   ;
  output        spi3_clk   ;
  output        spi4_clk   ;
  output        spi5_clk   ;
  output        spi7_clk   ;
  output        pos_edge   ;
  output        neg_edge   ;

//------------------------------------------------------------------------------
//internal signals
//------------------------------------------------------------------------------
  reg  [15:0] cnt     ;
  wire [15:0] cnt_nxt ;
  reg         spi_clk ;
  reg         spi0_clk;
  reg         spi1_clk;
  reg         spi2_clk;
  reg         spi3_clk;
  reg         spi4_clk;
  reg         spi5_clk;
  reg         spi7_clk;

//------------------------------------------------------------------------------
//beginning main code
//------------------------------------------------------------------------------
  //i_divider >0;
  // Counter counts half period
  assign cnt_nxt = cnt + 1'b1;
  always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)
      cnt      <= #1 16'h0;
    else
      if(soft_reset)
        cnt      <= #1 16'h0;
    else
      if (clkgen_en) begin
      if (cnt_nxt < spi_divider)
        cnt      <= #1 cnt_nxt;
      else
        cnt      <= #1 16'h0;
    end else
      cnt      <= #1 16'h0;
  end

always @*
    begin
  if(!spi_clk_en  )
    spi_clk  = spi_cpol;
  else
    if (~|spi_divider)
      spi_clk  = 1'b0;
  else
    spi_clk = (cnt >= {1'b0, spi_divider[15:1]});
end

always @(posedge clk or negedge rst_n) begin
  if(rst_n == 1'b0) begin
    spi0_clk <= #1 1'b0;
    spi1_clk <= #1 1'b0;
    spi2_clk <= #1 1'b0;
    spi3_clk <= #1 1'b0;
    spi4_clk <= #1 1'b0;
    spi5_clk <= #1 1'b0;
    spi7_clk <= #1 1'b0;
  end else
    begin
    spi0_clk <= #1 (spi_slv_sel== 'h0)?spi_clk:1'b0;
    spi1_clk <= #1 (spi_slv_sel== 'h1)?spi_clk:1'b0;
    spi2_clk <= #1 ((spi_slv_sel== 'h2)|(spi_slv_sel== 'h6))?spi_clk:1'b0;
    spi3_clk <= #1 (spi_slv_sel== 'h3)?spi_clk:1'b0;
    spi4_clk <= #1 (spi_slv_sel== 'h4)?spi_clk:1'b0;
    spi5_clk <= #1 (spi_slv_sel== 'h5)?spi_clk:1'b0;
    spi7_clk <= #1 (spi_slv_sel== 'h7)?spi_clk:1'b0;
  end
end

  // Pos and neg edge signals

  assign pos_edge = cnt=={1'b0,spi_divider[15 : 1]};
  assign neg_edge = ~|cnt                          ;
  
endmodule
