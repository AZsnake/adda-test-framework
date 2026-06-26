// Copyright (c) 2007-2012, INNOFIDEI Technologies. All Rights Reserved.
// INNOFIDEI Confidential Proprietary
// --------------------------------------------------------------------------
// FILE NAME : rf_cmd_arb.v
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
module rf_cmd_arb (
  input  wire [31:0] trigger_req,
  output wire        trigger_valid,
  output wire [ 4:0] trigger_num
);

//------------------------------------------------------------------------------
//internal signals
//------------------------------------------------------------------------------
  reg [4:0] trigger_num_r;
//------------------------------------------------------------------------------
//beginning main code
//------------------------------------------------------------------------------
always @* begin
  trigger_num_r = 5'h0;
  if (trigger_req[0])
    trigger_num_r = 5'h0;
  else if (trigger_req[1])
    trigger_num_r = 5'h1;
  else if (trigger_req[2])
    trigger_num_r = 5'h2;
  else if (trigger_req[3])
    trigger_num_r = 5'h3;
  else if (trigger_req[4])
    trigger_num_r = 5'h4;
  else if (trigger_req[5])
    trigger_num_r = 5'h5;
  else if (trigger_req[6])
    trigger_num_r = 5'h6;
  else if (trigger_req[7])
    trigger_num_r = 5'h7;
  else if (trigger_req[8])
    trigger_num_r = 5'h8;
  else if (trigger_req[9])
    trigger_num_r = 5'h9;
  else if (trigger_req[10])
    trigger_num_r = 5'ha;
  else if (trigger_req[11])
    trigger_num_r = 5'hb;
  else if (trigger_req[12])
    trigger_num_r = 5'hc;
  else if (trigger_req[13])
    trigger_num_r = 5'hd;
  else if (trigger_req[14])
    trigger_num_r = 5'he;
  else if (trigger_req[15])
    trigger_num_r = 5'hf;
  else if (trigger_req[16])
    trigger_num_r = 5'h10;
  else if (trigger_req[17])
    trigger_num_r = 5'h11;
  else if (trigger_req[18])
    trigger_num_r = 5'h12;
  else if (trigger_req[19])
    trigger_num_r = 5'h13;
  else if (trigger_req[20])
    trigger_num_r = 5'h14;
  else if (trigger_req[21])
    trigger_num_r = 5'h15;
  else if (trigger_req[22])
    trigger_num_r = 5'h16;
  else if (trigger_req[23])
    trigger_num_r = 5'h17;
  else if (trigger_req[24])
    trigger_num_r = 5'h18;
  else if (trigger_req[25])
    trigger_num_r = 5'h19;
  else if (trigger_req[26])
    trigger_num_r = 5'h1a;
  else if (trigger_req[27])
    trigger_num_r = 5'h1b;
  else if (trigger_req[28])
    trigger_num_r = 5'h1c;
  else if (trigger_req[29])
    trigger_num_r = 5'h1d;
  else if (trigger_req[30])
    trigger_num_r = 5'h1e;
  else if (trigger_req[31])
    trigger_num_r = 5'h1f;
end

assign trigger_valid = |trigger_req;
assign trigger_num   = trigger_num_r;

endmodule
