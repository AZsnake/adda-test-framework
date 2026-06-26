// Copyright (c) 2007-2012, INNOFIDEI Technologies. All Rights Reserved.
// INNOFIDEI Confidential Proprietary
// --------------------------------------------------------------------------
// FILE NAME : spi_ctrl_state.v
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
module gpo_cmd_state (
  //globals
  clk                 ,
  rst_n               ,
  //input
  soft_reset          ,
  trigger_valid       ,
  trigger_cmd         ,
  trigger_num         ,
  ram_ack             ,
  ram_read_addr       ,
  ram_rdata           ,
  ram_rdata_valid     ,
  ram_read_valid      ,

  trigger_done        ,
  trigger_done_num    ,

  soft_set_gpo1       ,
  soft_gpo1           ,

  soft_set_gpo2       ,
  soft_gpo2           ,

  gpo                 ,
  gpo_cmd_currentstate

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
  input         ram_ack             ;
  output  [8:0] ram_read_addr       ;
  input  [31:0] ram_rdata           ;
  input         ram_rdata_valid     ;
  output        ram_read_valid      ;

  output        trigger_done        ;
  output  [4:0] trigger_done_num    ;

  input         soft_set_gpo1       ;
  input  [30:0] soft_gpo1           ;

  input         soft_set_gpo2       ;
  input  [30:0] soft_gpo2           ;

  output [61:0] gpo                 ;
  output  [2:0] gpo_cmd_currentstate;

//------------------------------------------------------------------------------
//parameter define
//------------------------------------------------------------------------------
  parameter GPO_CMD_IDLE    = 3'h0,
            GPO_TRIGGER     = 3'h1,
            GPO_CMD_READ1   = 3'h2,
            GPO_CMD_READ2   = 3'h3,
            GPO_TIMER       = 3'h4,
            GPO_CMD         = 3'h5;
//------------------------------------------------------------------------------
//internal signals
//------------------------------------------------------------------------------
  reg   [2:0] gpo_cmd_currentstate;
  reg   [2:0] gpo_cmd_nextstate   ;
  reg  [62:0] timer_cnt           ;
  reg   [8:0] ram_read_addr       ;
  reg   [7:0] cmd_cnt             ;
  reg  [63:0] gpo_cmd             ;
  reg  [61:0] gpo                 ;
  wire        set_gpo_grp1        ;
  wire        set_gpo_grp2        ;
  reg         ram_read_valid      ;
  reg   [4:0] trigger_done_num    ;

//------------------------------------------------------------------------------
//beginning main code
//------------------------------------------------------------------------------
always@(posedge clk or negedge rst_n) begin
  if(!rst_n)
    gpo_cmd_currentstate <= #1 'h0;
  else
    if(soft_reset)
      gpo_cmd_currentstate <= #1 'h0;
  else
    gpo_cmd_currentstate <= #1 gpo_cmd_nextstate;
end

always@*
    begin
      case(gpo_cmd_currentstate)
      GPO_CMD_IDLE  :
      if(trigger_valid)
      gpo_cmd_nextstate = GPO_TRIGGER;
      else
      gpo_cmd_nextstate = GPO_CMD_IDLE;
      GPO_TRIGGER:
      if(cmd_cnt=='h0)
      gpo_cmd_nextstate = GPO_CMD_IDLE;
      else
      gpo_cmd_nextstate = GPO_CMD_READ1;
      GPO_CMD_READ1 :
      if(ram_rdata_valid)
      gpo_cmd_nextstate = GPO_CMD_READ2;
      else
      gpo_cmd_nextstate = GPO_CMD_READ1;
      GPO_CMD_READ2 :
      if(ram_rdata_valid)
      //           if(ram_rdata[31])
      if(gpo_cmd[63])
      gpo_cmd_nextstate = GPO_TIMER;
      else
      gpo_cmd_nextstate = GPO_CMD;
      else
      gpo_cmd_nextstate = GPO_CMD_READ2;
      GPO_TIMER:
      if(timer_cnt== 63'h0)
      gpo_cmd_nextstate = GPO_TRIGGER;
      else
      gpo_cmd_nextstate = GPO_TIMER;
      GPO_CMD:
      gpo_cmd_nextstate = GPO_TRIGGER;
      default:
      gpo_cmd_nextstate = gpo_cmd_currentstate;
      endcase
end

always@(posedge clk or negedge rst_n) begin
  if(!rst_n)
    ram_read_valid   <= #1  1'b0;
  else
    if(soft_reset)
      ram_read_valid   <= #1  1'b0;
  else
    if( ((gpo_cmd_nextstate == GPO_CMD_READ1)&(gpo_cmd_currentstate != GPO_CMD_READ1))|
       ((gpo_cmd_nextstate == GPO_CMD_READ2)&(gpo_cmd_currentstate != GPO_CMD_READ2)))
  ram_read_valid   <= #1 1'b1 ;
  else
    if(ram_ack )
      ram_read_valid   <= #1  1'b0;
end

always@(posedge clk or negedge rst_n) begin
  if(!rst_n)
    cmd_cnt          <= #1 'h0;
  else
    if(soft_reset)
      cmd_cnt          <= #1 'h0;
  else
    if((gpo_cmd_currentstate==GPO_CMD_IDLE)&trigger_valid)
      cmd_cnt <= #1 trigger_cmd[16:9];
  else
    if((gpo_cmd_currentstate==GPO_CMD)&(gpo_cmd_nextstate==GPO_TRIGGER)|
       (gpo_cmd_currentstate==GPO_TIMER)&(gpo_cmd_nextstate==GPO_TRIGGER)
       )
  if(cmd_cnt =='h0)
    cmd_cnt          <= #1 'h0;
  else
    cmd_cnt          <= #1 cmd_cnt - 'h1;
end

always@(posedge clk or negedge rst_n) begin
  if(!rst_n)
    ram_read_addr    <= #1 'h0;
  else
    if(soft_reset)
      ram_read_addr    <= #1 'h0;
  else
    if((gpo_cmd_currentstate==GPO_CMD_IDLE)&trigger_valid)
      ram_read_addr <= #1 trigger_cmd[8:0];
  else
    if(((gpo_cmd_currentstate==GPO_CMD_READ1)&(gpo_cmd_nextstate==GPO_CMD_READ2))|
       ((gpo_cmd_currentstate==GPO_CMD_READ2)&ram_rdata_valid))
  ram_read_addr    <= #1 ram_read_addr + 'h1;
end

always@(posedge clk or negedge rst_n) begin
  if(!rst_n)
    gpo_cmd          <= #1 'h0;
  else
    if(soft_reset)
      gpo_cmd          <= #1 'h0;
  else
    if((gpo_cmd_currentstate==GPO_CMD_READ1)&ram_rdata_valid)
      gpo_cmd[63:32] <= #1 ram_rdata;
  else
    if((gpo_cmd_currentstate==GPO_CMD_READ2)&ram_rdata_valid)
      gpo_cmd[31:0] <= #1 ram_rdata;
end

always@(posedge clk or negedge rst_n) begin
  if(!rst_n)
    timer_cnt        <= #1 63'h0;
  else
    if(soft_reset)
      timer_cnt        <= #1 63'h0;
  else
    if((gpo_cmd_currentstate==GPO_CMD_READ2)&(gpo_cmd_nextstate==GPO_TIMER))
      timer_cnt <= #1 {ram_rdata[30:0],gpo_cmd[31:0]};
  else
    if(timer_cnt == 63'h0)
      timer_cnt        <= #1 63'h0;
  else
    timer_cnt        <= #1 timer_cnt - 'h1;
end

  assign set_gpo_grp1 = (gpo_cmd_currentstate==GPO_CMD)&!gpo_cmd[31];
  assign set_gpo_grp2 = (gpo_cmd_currentstate==GPO_CMD)&gpo_cmd[31] ;
  
always @(posedge clk or negedge rst_n) begin
  if(!rst_n)
    gpo              <= #1 62'h0;
  else
    if(soft_set_gpo1)
      gpo[30:0] <= #1 soft_gpo1;
  else
    if(soft_set_gpo2)
      gpo[61:31] <= #1 soft_gpo2;
  else
    if(set_gpo_grp1)
      gpo[30:0 ] <= #1 (gpo_cmd[30: 0] & gpo_cmd[62:32]) | (~gpo_cmd[30:0] & gpo[30:0]);
  else
    if(set_gpo_grp2)
      gpo[61:31] <= #1 (gpo_cmd[30: 0] & gpo_cmd[62:32]) | (~gpo_cmd[30:0] & gpo[61:31]);
end

always@(posedge clk or negedge rst_n) begin
  if(!rst_n)
    trigger_done_num <= #1 'h0;
  else
    if(soft_reset)
      trigger_done_num <= #1 'h0;
  else
    if((gpo_cmd_currentstate == GPO_CMD_IDLE)&trigger_valid)
      trigger_done_num <= #1 trigger_num;
end

assign trigger_done = (gpo_cmd_currentstate != GPO_CMD_IDLE)&(gpo_cmd_nextstate==GPO_CMD_IDLE);

endmodule
