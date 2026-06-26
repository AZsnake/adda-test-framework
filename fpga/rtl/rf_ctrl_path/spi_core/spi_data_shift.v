// Copyright (c) 2007-2012, INNOFIDEI Technologies. All Rights Reserved.
// INNOFIDEI Confidential Proprietary
// --------------------------------------------------------------------------
// FILE NAME : spi_data_shift.v
// AUTHOR :GaoBin
// AUTHOR'S EMAIL :
// -----------------------------------------------------------------------------
// RELEASE HISTORY
// VERSION    DATE          AUTHOR            DESCRIPTION
// 1.0        2010-12-05     gaobin            initial
// -----------------------------------------------------------------------------
// PURPOSE : spi data shift
// -----------------------------------------------------------------------------
// Clock Domains :
// Other :
// -FHDR------------------------------------------------------------------------
//------------------------------------------------------------------------------
// Module Declaration
//------------------------------------------------------------------------------
module spi_data_shift (
  clk        ,
  rst_n      ,
  soft_reset ,
  spi_slv_sel,
  spi_data   ,
  spi_start  ,
  spi_en     ,
  tx_shift   ,
  rx_shift   ,
  spi_miso   ,

  spi_rdata  ,

  spi0_mosi  ,
  spi1_mosi  ,
  spi2_mosi  ,
  spi3_mosi  ,
  spi4_mosi  ,
  spi5_mosi  ,
  spi7_mosi

  );


//------------------------------------------------------------------------------
// Inputs / Outputs
//------------------------------------------------------------------------------

  input         clk        ;
  input         rst_n      ;
  input         soft_reset ;

  input   [2:0] spi_slv_sel;
  input  [55:0] spi_data   ;
  input         spi_start  ;
  input         spi_en     ;
  input         tx_shift   ;
  input         rx_shift   ;
  input         spi_miso   ;

  output [55:0] spi_rdata  ;

  output        spi0_mosi  ;
  output        spi1_mosi  ;
  output        spi2_mosi  ;
  output        spi3_mosi  ;
  output        spi4_mosi  ;
  output        spi5_mosi  ;
  output        spi7_mosi  ;
//------------------------------------------------------------------------------
//internal signals
//------------------------------------------------------------------------------
  reg [55:0] tx_reg     ;
  reg [55:0] rx_reg     ;
  reg [05:0] rx_cnt     ;
  reg        rx_shift_d1;
  reg        rx_data    ;
  reg        spi_mosi   ;
  reg        spi0_mosi  ;
  reg        spi1_mosi  ;
  reg        spi2_mosi  ;
  reg        spi3_mosi  ;
  reg        spi4_mosi  ;
  reg        spi5_mosi  ;
  reg        spi7_mosi  ;
//------------------------------------------------------------------------------
//beginning main code
//------------------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
      rx_shift_d1 <= #1 1'b0;
    end else begin
      rx_shift_d1 <= #1 rx_shift;
    end
  end
  always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0)
      tx_reg     <= #1 56'b0;
    else
      if(soft_reset)
        tx_reg     <= #1 56'b0;
    else
      if (spi_start)
        tx_reg     <= #1 spi_data;
    else if (tx_shift & spi_en)
      tx_reg <= #1 {tx_reg[54:0],1'b0};
  end
  always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0)
      rx_cnt     <= #1 6'h0;
    else
      if(soft_reset)
        rx_cnt     <= #1 6'h0;
    else
      if(spi_start)
        rx_cnt     <= #1 6'h0;
    else
      if(rx_shift_d1 & spi_en)
        rx_cnt     <= #1 rx_cnt + 1'b1;
  end
  always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0)
      rx_data    <= #1 1'h0;
    else
      if(soft_reset)
        rx_data    <= #1 1'h0;
    else
      if(rx_shift)
        rx_data    <= #1 spi_miso;
  end
  wire sel_bank0 = (rx_cnt[5:3] == 3'h0);
  wire sel_bank1 = (rx_cnt[5:3] == 3'h1);
  wire sel_bank2 = (rx_cnt[5:3] == 3'h2);
  wire sel_bank3 = (rx_cnt[5:3] == 3'h3);
  wire sel_bank4 = (rx_cnt[5:3] == 3'h4);
  wire sel_bank5 = (rx_cnt[5:3] == 3'h5);
  wire sel_bank6 = (rx_cnt[5:3] == 3'h6);

  always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0)
      rx_reg[55:48] <= #1 8'b0;
    else
      if(soft_reset)
        rx_reg[55:48] <= #1 8'b0;
    else
      if (rx_shift_d1 & spi_en & sel_bank0) begin
      if (rx_cnt[2:0] == 3'h0)
        rx_reg[55] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h1)
        rx_reg[54] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h2)
        rx_reg[53] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h3)
        rx_reg[52] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h4)
        rx_reg[51] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h5)
        rx_reg[50] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h6)
        rx_reg[49] <= #1 rx_data;
      else
        rx_reg[48] <= #1 rx_data;
    end
  end
  always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0)
      rx_reg[47:40] <= #1 8'b0;
    else
      if(soft_reset)
        rx_reg[47:40] <= #1 8'b0;
    else
      if (rx_shift_d1 & spi_en & sel_bank1) begin
      if (rx_cnt[2:0] == 3'h0)
        rx_reg[47] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h1)
        rx_reg[46] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h2)
        rx_reg[45] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h3)
        rx_reg[44] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h4)
        rx_reg[43] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h5)
        rx_reg[42] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h6)
        rx_reg[41] <= #1 rx_data;
      else
        rx_reg[40] <= #1 rx_data;
    end
  end
  always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0)
      rx_reg[39:32] <= #1 8'b0;
    else
      if(soft_reset)
        rx_reg[39:32] <= #1 8'b0;
    else
      if (rx_shift_d1 & spi_en & sel_bank2) begin
      if (rx_cnt[2:0] == 3'h0)
        rx_reg[39] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h1)
        rx_reg[38] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h2)
        rx_reg[37] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h3)
        rx_reg[36] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h4)
        rx_reg[35] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h5)
        rx_reg[34] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h6)
        rx_reg[33] <= #1 rx_data;
      else
        rx_reg[32] <= #1 rx_data;
    end
  end
  always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0)
      rx_reg[31:24] <= #1 8'b0;
    else
      if(soft_reset)
        rx_reg[31:24] <= #1 8'b0;
    else
      if (rx_shift_d1 & spi_en & sel_bank3) begin
      if (rx_cnt[2:0] == 3'h0)
        rx_reg[31] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h1)
        rx_reg[30] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h2)
        rx_reg[29] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h3)
        rx_reg[28] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h4)
        rx_reg[27] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h5)
        rx_reg[26] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h6)
        rx_reg[25] <= #1 rx_data;
      else
        rx_reg[24] <= #1 rx_data;
    end
  end
  always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0)
      rx_reg[23:16] <= #1 8'b0;
    else
      if(soft_reset)
        rx_reg[23:16] <= #1 8'b0;
    else
      if (rx_shift_d1 & spi_en & sel_bank4) begin
      if (rx_cnt[2:0] == 3'h0)
        rx_reg[23] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h1)
        rx_reg[22] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h2)
        rx_reg[21] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h3)
        rx_reg[20] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h4)
        rx_reg[19] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h5)
        rx_reg[18] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h6)
        rx_reg[17] <= #1 rx_data;
      else
        rx_reg[16] <= #1 rx_data;
    end
  end
  always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0)
      rx_reg[15:8] <= #1 8'b0;
    else
      if(soft_reset)
        rx_reg[15:8] <= #1 8'b0;
    else
      if (rx_shift_d1 & spi_en & sel_bank5) begin
      if (rx_cnt[2:0] == 3'h0)
        rx_reg[15] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h1)
        rx_reg[14] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h2)
        rx_reg[13] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h3)
        rx_reg[12] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h4)
        rx_reg[11] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h5)
        rx_reg[10] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h6)
        rx_reg[9]  <= #1 rx_data;
      else
        rx_reg[8]  <= #1 rx_data;
    end
  end
  always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0)
      rx_reg[7:0] <= #1 8'b0;
    else
      if(soft_reset)
        rx_reg[7:0] <= #1 8'b0;
    else
      if (rx_shift_d1 & spi_en & sel_bank6) begin
      if (rx_cnt[2:0] == 3'h0)
        rx_reg[7] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h1)
        rx_reg[6] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h2)
        rx_reg[5] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h3)
        rx_reg[4] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h4)
        rx_reg[3] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h5)
        rx_reg[2] <= #1 rx_data;
      else if (rx_cnt[2:0] == 3'h6)
        rx_reg[1] <= #1 rx_data;
      else
        rx_reg[0] <= #1 rx_data;
    end
  end

always @(posedge clk or negedge rst_n) begin
  if (rst_n == 1'b0)
    spi0_mosi <= #1 1'b0;
  else
    if(spi_slv_sel=='h0)
      if(spi_start)
        spi0_mosi <= #1 spi_data[55];
  else
    if (tx_shift & spi_en)
      spi0_mosi <= #1 tx_reg[54];
  else
    spi0_mosi <= #1  spi0_mosi;
  else
    spi0_mosi <= #1 1'b0;
end

always @(posedge clk or negedge rst_n) begin
  if (rst_n == 1'b0)
    spi1_mosi <= #1 1'b0;
  else
    if(spi_slv_sel=='h1)
      if(spi_start)
        spi1_mosi <= #1 spi_data[55];
  else
    if (tx_shift & spi_en)
      spi1_mosi <= #1 tx_reg[54];
  else
    spi1_mosi <= #1  spi1_mosi;
  else
    spi1_mosi <= #1 1'b0;
end

always @(posedge clk or negedge rst_n) begin
  if (rst_n == 1'b0)
    spi2_mosi <= #1 1'b0;
  else
    if((spi_slv_sel=='h2)|(spi_slv_sel=='h6))
      if(spi_start)
        spi2_mosi <= #1 spi_data[55];
  else
    if (tx_shift & spi_en)
      spi2_mosi <= #1 tx_reg[54];
  else
    spi2_mosi <= #1  spi2_mosi;
  else
    spi2_mosi <= #1 1'b0;
end

always @(posedge clk or negedge rst_n) begin
  if (rst_n == 1'b0)
    spi3_mosi <= #1 1'b0;
  else
    if(spi_slv_sel=='h3)
      if(spi_start)
        spi3_mosi <= #1 spi_data[55];
  else
    if (tx_shift & spi_en)
      spi3_mosi <= #1 tx_reg[54];
  else
    spi3_mosi <= #1  spi3_mosi;
  else
    spi3_mosi <= #1 1'b0;
end

always @(posedge clk or negedge rst_n) begin
  if (rst_n == 1'b0)
    spi4_mosi <= #1 1'b0;
  else
    if(spi_slv_sel=='h4)
      if(spi_start)
        spi4_mosi <= #1 spi_data[55];
  else
    if (tx_shift & spi_en)
      spi4_mosi <= #1 tx_reg[54];
  else
    spi4_mosi <= #1  spi4_mosi;
  else
    spi4_mosi <= #1 1'b0;
end

always @(posedge clk or negedge rst_n) begin
  if (rst_n == 1'b0)
    spi5_mosi <= #1 1'b0;
  else
    if(spi_slv_sel=='h5)
      if(spi_start)
        spi5_mosi <= #1 spi_data[55];
  else
    if (tx_shift & spi_en)
      spi5_mosi <= #1 tx_reg[54];
  else
    spi5_mosi <= #1  spi5_mosi;
  else
    spi5_mosi <= #1 1'b0;
end

always @(posedge clk or negedge rst_n) begin
  if (rst_n == 1'b0)
    spi7_mosi <= #1 1'b0;
  else
    if(spi_slv_sel=='h7)
      if(spi_start)
        spi7_mosi <= #1 spi_data[55];
  else
    if (tx_shift & spi_en)
      spi7_mosi <= #1 tx_reg[54];
  else
    spi7_mosi <= #1  spi7_mosi;
  else
    spi7_mosi <= #1 1'b0;
end

  assign spi_rdata = rx_reg;
  
endmodule
