// Copyright (c) 2007-2012, INNOFIDEI Technologies. All Rights Reserved.
// INNOFIDEI Confidential Proprietary
// --------------------------------------------------------------------------
// FILE NAME : spi_cmd_state.v
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
module spi_cmd_state (
  //globals
  clk                 ,
  rst_n               ,
  //input
  soft_reset          ,
  trigger_valid       ,
  trigger_cmd         ,
  trigger_num         ,
  spi_split_interval  ,

  spi_iir             ,
  spi_iir_en          ,
  spi_iir_done        ,
  spi_iir_rdata       ,

  spi_batch_cmd       ,
  spi_batch_en        ,
  spi_batch_done      ,

  ram_ack             ,
  ram_read_addr       ,
  ram_rdata           ,
  ram_rdata_valid     ,
  ram_read_valid      ,
  ram_write_valid     ,
  ram_write_addr      ,
  ram_wdata           ,

  spi_cmd_valid       ,
  spi_cmd             ,
  spi_cmd_done        ,
  trigger_done        ,
  trigger_done_num    ,
  spi_rdata           ,
  spi_cmd_currentstate
  );


//------------------------------------------------------------------------------
// Inputs / Outputs
//------------------------------------------------------------------------------

  input         clk                 ;
  input         rst_n               ;

//output
  input         soft_reset          ;

  input         trigger_valid       ;
  input  [16:0] trigger_cmd         ;
  input   [4:0] trigger_num         ;

  input   [6:0] spi_split_interval  ;

  input  [62:0] spi_iir             ;
  input         spi_iir_en          ;
  output        spi_iir_done        ;
  output [55:0] spi_iir_rdata       ;

  input  [16:0] spi_batch_cmd       ;
  input         spi_batch_en        ;
  output        spi_batch_done      ;

  input         ram_ack             ;
  output  [8:0] ram_read_addr       ;
  input  [31:0] ram_rdata           ;
  input         ram_rdata_valid     ;
  output        ram_read_valid      ;
  output        ram_write_valid     ;
  output  [8:0] ram_write_addr      ;
  output [31:0] ram_wdata           ;

  output        spi_cmd_valid       ;
  output [62:0] spi_cmd             ;
  input         spi_cmd_done        ;

  output        trigger_done        ;
  output  [4:0] trigger_done_num    ;

  input  [55:0] spi_rdata           ;
  output  [3:0] spi_cmd_currentstate;

//------------------------------------------------------------------------------
//parameter define
//------------------------------------------------------------------------------
  parameter SPI_CMD_IDLE      = 4'h0,
            SPI_IIR           = 4'h1,
            SPI_BATCH         = 4'h2,
            SPI_TRIGGER       = 4'h3,
            SPI_CMD_READ1     = 4'h4,
            SPI_CMD_READ2     = 4'h5,
            SPI_CMD           = 4'h6,
            SPI_WRITE_RAM1    = 4'h7,
            SPI_WRITE_RAM2    = 4'h8,
            SPI_WAIT          = 4'h9;

//------------------------------------------------------------------------------
//internal signals
//------------------------------------------------------------------------------
  reg   [3:0] spi_cmd_currentstate;
  reg   [3:0] spi_cmd_nextstate   ;
  reg   [6:0] spi_interval_cnt    ;
  reg   [8:0] ram_read_addr       ;
  reg   [1:0] spi_cmd_mode        ;
  reg   [7:0] cmd_cnt             ;
  reg         spi_ins64_valid     ;
  reg   [8:0] ram_write_addr      ;
  reg  [62:0] spi_cmd             ;
  reg         ram_write_valid     ;
  wire        spi_read_valid      ;
  reg         ram_read_valid      ;
  reg   [4:0] trigger_done_num    ;
  reg  [55:0] spi_iir_rdata       ;
  reg         spi_cmd_valid       ;
//------------------------------------------------------------------------------
//beginning main code
//------------------------------------------------------------------------------
always@(posedge clk or negedge rst_n) begin
  if(!rst_n)
    spi_cmd_currentstate <= #1 'h0;
  else
    if(soft_reset)
      spi_cmd_currentstate <= #1 'h0;
  else
    spi_cmd_currentstate <= #1 spi_cmd_nextstate;
end

always@*
    begin
      case(spi_cmd_currentstate)
      SPI_CMD_IDLE  :
      if(spi_iir_en)
      spi_cmd_nextstate = SPI_IIR;
      else
      if(spi_batch_en)
      spi_cmd_nextstate = SPI_BATCH;
      else
      if(trigger_valid)
      spi_cmd_nextstate = SPI_TRIGGER;
      else
      spi_cmd_nextstate = SPI_CMD_IDLE;
      SPI_IIR     :
      spi_cmd_nextstate = SPI_CMD;
      SPI_BATCH   :
      if(cmd_cnt=='h0)
      spi_cmd_nextstate = SPI_CMD_IDLE;
      else
      spi_cmd_nextstate = SPI_CMD_READ1;
      SPI_TRIGGER :
      if(cmd_cnt=='h0)
      spi_cmd_nextstate = SPI_CMD_IDLE;
      else
      spi_cmd_nextstate = SPI_CMD_READ1;
      SPI_CMD_READ1 :
      if(ram_rdata_valid)
      if(ram_rdata[25])
      spi_cmd_nextstate = SPI_CMD_READ2;
      else
      spi_cmd_nextstate = SPI_CMD;
      else
      spi_cmd_nextstate = SPI_CMD_READ1;
      SPI_CMD_READ2 :
      if(ram_rdata_valid)
      spi_cmd_nextstate = SPI_CMD;
      else
      spi_cmd_nextstate = SPI_CMD_READ2;
      SPI_CMD:
      if(spi_cmd_done)
      if(spi_read_valid&(spi_cmd_mode !=2'b0) )
      spi_cmd_nextstate = SPI_WRITE_RAM1;
      else
      spi_cmd_nextstate = SPI_WAIT;
      else
      spi_cmd_nextstate = SPI_CMD;
      SPI_WRITE_RAM1:
      if(ram_ack)
      if(spi_ins64_valid)
      spi_cmd_nextstate = SPI_WRITE_RAM2;
      else
      spi_cmd_nextstate = SPI_WAIT;
      else
      spi_cmd_nextstate = SPI_WRITE_RAM1;
      SPI_WRITE_RAM2:
      if(ram_ack)
      spi_cmd_nextstate = SPI_WAIT;
      else
      spi_cmd_nextstate = SPI_WRITE_RAM1;
      SPI_WAIT :
      if(spi_interval_cnt=='h0)
      case(spi_cmd_mode)
        2'b00  : spi_cmd_nextstate = SPI_CMD_IDLE; //IIR
        2'b01  : spi_cmd_nextstate = SPI_BATCH   ; //batch
        2'b10  : spi_cmd_nextstate = SPI_TRIGGER ; //trigger
        default: spi_cmd_nextstate = SPI_CMD_IDLE;
      endcase
    else
    spi_cmd_nextstate = SPI_WAIT;
    default:
    spi_cmd_nextstate = spi_cmd_currentstate;
      endcase
end

assign trigger_done   = (spi_cmd_currentstate==SPI_TRIGGER)&(spi_cmd_nextstate == SPI_CMD_IDLE)      ;

assign spi_iir_done   = (spi_cmd_currentstate==SPI_WAIT)&(spi_cmd_mode==2'b0)&(spi_interval_cnt=='h0);

assign spi_batch_done = (spi_cmd_currentstate== SPI_BATCH)&(spi_cmd_nextstate == SPI_CMD_IDLE)       ;

always@(posedge clk or negedge rst_n) begin
  if(!rst_n)
    trigger_done_num  <= #1 'h0;
  else
    if((spi_cmd_currentstate==SPI_CMD_IDLE)&(spi_cmd_nextstate == SPI_TRIGGER))
      trigger_done_num  <= #1 trigger_num;
end

assign spi_read_valid = spi_cmd[56];

always@(posedge clk or negedge rst_n) begin
  if(!rst_n)
    spi_cmd_mode      <= #1 2'b0;
  else
    if(soft_reset)
      spi_cmd_mode      <= #1 2'b0;
  else
    if((spi_cmd_currentstate==SPI_CMD_IDLE)&spi_iir_en)
      spi_cmd_mode      <= #1 2'b0;
  else
    if((spi_cmd_currentstate==SPI_CMD_IDLE)&spi_batch_en)
      spi_cmd_mode      <= #1 2'b01;
  else
    if((spi_cmd_currentstate==SPI_CMD_IDLE)&trigger_valid)
      spi_cmd_mode      <= #1 2'b10;
end

always@(posedge clk or negedge rst_n) begin
  if(!rst_n)
    cmd_cnt           <= #1 'h0;
  else
    if(soft_reset)
      cmd_cnt           <= #1 'h0;
  else
    if((spi_cmd_currentstate==SPI_CMD_IDLE)&trigger_valid)
      cmd_cnt <= #1 (trigger_cmd[16:9] );
  else
    if((spi_cmd_currentstate==SPI_CMD_IDLE)&spi_batch_en)
      cmd_cnt <= #1 (spi_batch_cmd[16:9]);
  else
    if((spi_cmd_currentstate==SPI_CMD)&spi_cmd_done)
      cmd_cnt           <= #1 cmd_cnt - 'h1;
end

always@(posedge clk or negedge rst_n) begin
  if(!rst_n)
    spi_ins64_valid   <= #1 'h0;
  else
    if(soft_reset)
      spi_ins64_valid   <= #1 'h0;
  else
    if((spi_cmd_currentstate==SPI_CMD_READ1)&ram_rdata_valid)
      spi_ins64_valid   <= #1 ram_rdata[25];
  else
    if(spi_cmd_currentstate == SPI_IIR)
      spi_ins64_valid   <= #1 spi_iir[57];
end

always@(posedge clk or negedge rst_n) begin
  if(!rst_n)
    ram_read_valid    <= #1 1'b0;
  else
    if(soft_reset)
      ram_read_valid    <= #1 1'b0;
  else
    if(
       ((spi_cmd_nextstate == SPI_CMD_READ1)&( spi_cmd_currentstate != SPI_CMD_READ1))|
       ((spi_cmd_nextstate == SPI_CMD_READ2)&( spi_cmd_currentstate != SPI_CMD_READ2))
       )
  ram_read_valid    <= #1 1'b1;
  else
    if(ram_ack)
      ram_read_valid    <= #1 1'b0;
end

always@(posedge clk or negedge rst_n) begin
  if(!rst_n)
    ram_read_addr     <= #1 'h0;
  else
    if(soft_reset)
      ram_read_addr     <= #1 'h0;
  else
    if((spi_cmd_currentstate==SPI_CMD_IDLE)&spi_batch_en)
      ram_read_addr <= #1 spi_batch_cmd[8:0];
  else
    if((spi_cmd_currentstate==SPI_CMD_IDLE)&trigger_valid)
      ram_read_addr <= #1 trigger_cmd[8:0];
  else
    if(((spi_cmd_currentstate==SPI_CMD_READ1)&ram_rdata_valid)|
       ((spi_cmd_currentstate==SPI_CMD_READ2)&ram_rdata_valid))
  ram_read_addr     <= #1 ram_read_addr + 'h1;
end

always@(posedge clk or negedge rst_n) begin
  if(!rst_n)
    ram_write_addr    <= #1 'h0;
  else
    if(soft_reset)
      ram_write_addr    <= #1 'h0;
  else
    if((spi_cmd_currentstate==SPI_CMD_READ1)&ram_rdata_valid)
      ram_write_addr    <= #1 ram_read_addr;
  else
    if((spi_cmd_currentstate==SPI_WRITE_RAM1)&(spi_cmd_nextstate==SPI_WRITE_RAM2))
      ram_write_addr    <= #1 ram_write_addr + 'h1;
end

always@(posedge clk or negedge rst_n) begin
  if(!rst_n)
    ram_write_valid   <= #1 1'b0;
  else
    if(soft_reset)
      ram_write_valid   <= #1 1'b0;
  else
    if((spi_cmd_nextstate == SPI_WRITE_RAM1)|(spi_cmd_nextstate == SPI_WRITE_RAM2))
      ram_write_valid   <= #1 1'b1;
  else
    if(ram_ack)
      ram_write_valid   <= #1 1'b0;
end

always@(posedge clk or negedge rst_n) begin
  if(!rst_n)
    spi_interval_cnt  <= #1 6'h0;
  else
    if(soft_reset)
      spi_interval_cnt  <= #1 6'h0;
  else
    if((spi_cmd_nextstate == SPI_WAIT)&( spi_cmd_currentstate != SPI_WAIT))
      spi_interval_cnt  <= #1 spi_split_interval;
  else
    if(spi_interval_cnt != 6'h0)
      spi_interval_cnt  <= #1 spi_interval_cnt - 6'h1;
end

assign ram_wdata = (spi_cmd_currentstate == SPI_WRITE_RAM1)?{8'b0,spi_rdata[55:32]} : spi_rdata[31:0];

always@(posedge clk or negedge rst_n) begin
  if(!rst_n)
    spi_cmd_valid     <= #1 4'h0;
  else
    if(soft_reset)
      spi_cmd_valid     <= #1 4'h0;
  else
    spi_cmd_valid     <= #1 (spi_cmd_nextstate ==SPI_CMD)&(spi_cmd_currentstate != SPI_CMD);
end

always@(posedge clk or negedge rst_n) begin
  if(!rst_n)
    spi_cmd           <= #1 'h0;
  else
    if(soft_reset)
      spi_cmd           <= #1 'h0;
  else
    if((spi_cmd_currentstate==SPI_CMD_IDLE)&spi_iir_en)
      spi_cmd           <= #1 spi_iir;
  else
    if(ram_rdata_valid)
      if(spi_cmd_currentstate ==SPI_CMD_READ2)
        spi_cmd[31:0] <= #1 ram_rdata;
  else
    if(spi_cmd_currentstate ==SPI_CMD_READ1)
      spi_cmd[62:32] <= #1 ram_rdata;
  else
    spi_cmd           <= #1  spi_cmd;
  else
    spi_cmd           <= #1 spi_cmd;
end
always@(posedge clk or negedge rst_n) begin
  if(!rst_n)
    spi_iir_rdata     <= #1 'h0;
  else
    if(soft_reset)
      spi_iir_rdata     <= #1 'h0;
  else
    if(spi_cmd_done)
      spi_iir_rdata     <= #1 spi_rdata;
end

endmodule
