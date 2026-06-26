module rf_async_fifo (
  i_r_clk        ,
  i_r_rstn       ,
  i_w_clk        ,
  i_w_rstn       ,
  soft_reset_rclk,
  soft_reset_wclk,
  i_r_en         ,
  i_w_en         ,
  i_wdata        ,
  o_rdata        ,
  o_rdata_valid  ,
  o_r_empty      ,
  o_w_full       ,
  o_r_almst_empty,
  o_w_almst_full ,
  o_r_fifo_num
  );

  parameter DATA_WIDTH = 14;
//------------------------------------------------------------------------------
// Inputs / Outputs
//------------------------------------------------------------------------------
  input                         i_r_clk        ;
  input                         i_r_rstn       ;
  input                         i_w_clk        ;
  input                         i_w_rstn       ;
  input                         soft_reset_rclk;
  input                         soft_reset_wclk;
  input                         i_r_en         ;
  input                         i_w_en         ;
  input  [((2*DATA_WIDTH)-1):0] i_wdata        ;
  output [((2*DATA_WIDTH)-1):0] o_rdata        ;
  output                        o_rdata_valid  ;
  output                        o_r_empty      ;
  output                        o_w_full       ;
  output                        o_r_almst_empty;
  output                        o_w_almst_full ;
  output                  [3:0] o_r_fifo_num   ;
//------------------------------------------------------------------------------
//internal signals
//------------------------------------------------------------------------------
  wire                  [2:0] ram_radr      ;
  wire                  [2:0] ram_wadr      ;
  reg  [((2*DATA_WIDTH)-1):0] o_rdata       ;

  reg  [((2*DATA_WIDTH)-1):0] mem_data [7:0];
  reg                         o_rdata_valid ;
//------------------------------------------------------------------------------
//beginning main code
//------------------------------------------------------------------------------
rf_async_ff  u_rf_async_ff
(
  .i_r_clk          (i_r_clk        ),
  .i_r_rstn         (i_r_rstn       ),
  .i_w_clk          (i_w_clk        ),
  .i_w_rstn         (i_w_rstn       ),
  .i_r_en           (i_r_en         ),
  .i_w_en           (i_w_en         ),
  .i_r_clr          (soft_reset_rclk ),
  .i_w_clr          (soft_reset_wclk ),
  .o_r_empty        (o_r_empty      ),
  .o_w_full         (o_w_full       ),
  .o_r_almst_empty  (o_r_almst_empty),
  .o_w_almst_full   (o_w_almst_full ),
  .o_r_fifo_num     (o_r_fifo_num  ),
  .o_w_space_num    (  ),
  .o_w_fifo_num     (  ),
  .o_ram_radr       (ram_radr     ),
  .o_ram_wadr	    (ram_wadr	  )
);

always@(posedge i_w_clk or negedge i_w_rstn) begin
  if(!i_w_rstn) begin
    mem_data[0] <= 'h0;
    mem_data[1] <= 'h0;
    mem_data[2] <= 'h0;
    mem_data[3] <= 'h0;
    mem_data[4] <= 'h0;
    mem_data[5] <= 'h0;
    mem_data[6] <= 'h0;
    mem_data[7] <= 'h0;
  end else
    begin
    mem_data[0] <= (i_w_en&(ram_wadr==3'h0))?i_wdata: mem_data[0];
    mem_data[1] <= (i_w_en&(ram_wadr==3'h1))?i_wdata: mem_data[1];
    mem_data[2] <= (i_w_en&(ram_wadr==3'h2))?i_wdata: mem_data[2];
    mem_data[3] <= (i_w_en&(ram_wadr==3'h3))?i_wdata: mem_data[3];
    mem_data[4] <= (i_w_en&(ram_wadr==3'h4))?i_wdata: mem_data[4];
    mem_data[5] <= (i_w_en&(ram_wadr==3'h5))?i_wdata: mem_data[5];
    mem_data[6] <= (i_w_en&(ram_wadr==3'h6))?i_wdata: mem_data[6];
    mem_data[7] <= (i_w_en&(ram_wadr==3'h7))?i_wdata: mem_data[7];
  end
end

always@(posedge i_r_clk or negedge i_r_rstn) begin
  if(!i_r_rstn)
    o_rdata       <= #1 'h0;
  else
    if(i_r_en)
      o_rdata       <= #1 mem_data[ram_radr];
end

always@(posedge i_r_clk or negedge i_r_rstn) begin
  if(!i_r_rstn)
    o_rdata_valid <= #1 1'b0;
  else
    o_rdata_valid <= #1 i_r_en;
end

endmodule
