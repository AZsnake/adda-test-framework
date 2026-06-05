// Copyright (c) 2007-2012, INNOFIDEI Technologies. All Rights Reserved.
// INNOFIDEI Confidential Proprietary
// --------------------------------------------------------------------------
// FILE NAME : rf_spram_mux.v
// AUTHOR :: zhaop
// -----------------------------------------------------------------------------
// RELEASE HISTORY
// VERSION    DATE          AUTHOR            DESCRIPTION
// 1.0        2012-2-9     zhaop
// -----------------------------------------------------------------------------
// PURPOSE :
// -----------------------------------------------------------------------------
// Clock Domains :
// Other :
// -FHDR------------------------------------------------------------------------
//------------------------------------------------------------------------------
// Module Declaration
//------------------------------------------------------------------------------
module rf_spram_mux (
  //globals
  clk                ,
  rst_n              ,
  //
  //config bus
  cpu_sram_wr        ,
  cpu_sram_rd        ,
  cpu_sram_addr      ,
  cpu_sram_wdata     ,
  cpu_sram_rdata     ,
  //gposram_read port
  gposram_read_valid ,
  gposram_ram_ack    ,
  gposram_read_addr  ,

  gposram_rdata      ,
  gposram_rdata_valid,

  //spisram read writeport
  spisram_read_valid ,
  spisram_write_valid,
  spisram_ram_ack    ,
  spisram_read_addr  ,
  spisram_write_addr ,
  spisram_wdata      ,

  spisram_rdata      ,
  spisram_rdata_valid,


  spram_en           ,
  spram_we           ,
  spram_addr         ,
  spram_wdata        ,
  spram_rdata

  );


//------------------------------------------------------------------------------
// Inputs / Outputs
//------------------------------------------------------------------------------
//globals
  input         clk                ;
  input         rst_n              ;

//config bus
  input         cpu_sram_wr        ;
  input         cpu_sram_rd        ;
  input   [8:0] cpu_sram_addr      ;
  input  [31:0] cpu_sram_wdata     ;
  output [31:0] cpu_sram_rdata     ;
//gposram_read port
  input         gposram_read_valid ;
  output        gposram_ram_ack    ;
  input   [8:0] gposram_read_addr  ;
  output [31:0] gposram_rdata      ;
  output        gposram_rdata_valid;
//spisram read writeport
  input         spisram_read_valid ;
  input         spisram_write_valid;
  output        spisram_ram_ack    ;
  input   [8:0] spisram_read_addr  ;
  input   [8:0] spisram_write_addr ;
  input  [31:0] spisram_wdata      ;
  output [31:0] spisram_rdata      ;
  output        spisram_rdata_valid;

  output        spram_en           ;
  output        spram_we           ;
  output  [8:0] spram_addr         ;
  output [31:0] spram_wdata        ;
  input  [31:0] spram_rdata        ;

//------------------------------------------------------------------------------
//internal signals
//------------------------------------------------------------------------------
  reg        spram_we               ;
  reg  [8:0] spram_addr             ;
  reg [31:0] spram_wdata            ;

  reg        gposram_rdata_valid    ;
  reg        spisram_rdata_valid    ;
  reg [31:0] spram_rdata_d1         ;
  reg        spram_en_d1            ;

  reg        gposram_rdata_valid_pre;
  reg        spisram_rdata_valid_pre;
//------------------------------------------------------------------------------
//beginning main code
//------------------------------------------------------------------------------

  assign spram_en = cpu_sram_wr|cpu_sram_rd|gposram_read_valid|spisram_read_valid|spisram_write_valid;
  
always@*
  begin
  if(cpu_sram_wr|cpu_sram_rd) begin
    spram_we    = cpu_sram_wr;
    spram_addr  = cpu_sram_addr;
    spram_wdata = cpu_sram_wr?cpu_sram_wdata:32'b0;
  end else
    if(gposram_read_valid) begin
    spram_we    = 1'b0;
    spram_addr  = gposram_read_addr;
    spram_wdata = 32'b0;
  end else
    if(spisram_read_valid|spisram_write_valid) begin
    spram_we    = spisram_write_valid;
    spram_addr = spisram_write_valid?spisram_write_addr:spisram_read_addr;
    spram_wdata = spisram_write_valid?spisram_wdata:32'b0;
  end else
    begin
    spram_we    = 1'h0;
    spram_addr  = 9'h0;
    spram_wdata = 32'h0;
  end
end

assign gposram_ram_ack = !(cpu_sram_wr|cpu_sram_rd)                   ;
assign spisram_ram_ack = !(cpu_sram_wr|cpu_sram_rd|gposram_read_valid);

always@(posedge clk or negedge rst_n) begin
  if(!rst_n)
    spram_en_d1             <= 1'b0;
  else
    spram_en_d1             <= spram_en;
end

always@(posedge clk or negedge rst_n) begin
  if(!rst_n)
    spram_rdata_d1          <= #1 32'b0;
  else
    if(spram_en_d1)
      spram_rdata_d1          <= #1 spram_rdata;
end

always@(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    gposram_rdata_valid_pre <= #1 1'b0;
    spisram_rdata_valid_pre <= #1 1'b0;
    gposram_rdata_valid     <= #1 1'b0;
    spisram_rdata_valid     <= #1 1'b0;
  end else
    begin
    gposram_rdata_valid_pre <= #1 gposram_read_valid&gposram_ram_ack;
    spisram_rdata_valid_pre <= #1 spisram_read_valid&spisram_ram_ack;
    gposram_rdata_valid     <= #1 gposram_rdata_valid_pre;
    spisram_rdata_valid     <= #1 spisram_rdata_valid_pre;
  end
end

assign gposram_rdata  = spram_rdata_d1;
assign spisram_rdata  = spram_rdata_d1;
assign cpu_sram_rdata = spram_rdata_d1;

endmodule
