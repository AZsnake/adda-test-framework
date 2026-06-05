// Pack UART register access into rf_spi_core spi_cmd (per-chip frame format).
module uart_spi_pack (
  input  wire  [7:0] chip_id  ,
  input  wire  [7:0] cmd      ,
  input  wire  [7:0] addr     ,
  input  wire  [7:0] wdata    ,
  input  wire  [1:0] sub_idx  ,
  input  wire [55:0] spi_rdata,

  output wire [62:0] spi_cmd  ,
  output wire  [1:0] frame_cnt,
  output wire        bad_chip ,
  output wire  [7:0] rd_byte
  );


  wire [2:0] slv_sel =
                       (chip_id == 8'h01) ? 3'd0 :
                       (chip_id == 8'h02) ? 3'd1 :
                       (chip_id == 8'h03) ? 3'd2 : 3'd7;

  assign bad_chip  = (slv_sel == 3'd7) ||
                      ((chip_id == 8'h03) && (addr[7:5] != 3'b000));
  
  assign frame_cnt = (chip_id == 8'h01) ? 2'd2 : 2'd1;
  
  wire        is_read      = (cmd == 8'h02);

  // 16-bit word: R/W(15), W1/W0(14:13), addr[12:0]
  wire [15:0] ad9640_instr =
                             is_read ? {1'b1, 2'b00, 5'h0, addr[7:0]} :
                             {1'b0, 2'b00, 5'h0, addr[7:0]};

  wire [15:0] ad9117_frame =
                             is_read ? {1'b1, 2'b00, addr[4:0], 8'h00} :
                             {1'b0, 2'b00, addr[4:0], wdata[7:0]};

  wire [15:0] si5340_frame =
                             (sub_idx == 2'd0) ? {8'h00, addr[7:0]} :
                             is_read           ? {8'h80, 8'hff} :
                             {8'h40, wdata[7:0]};

  // rf_spi_core shifts MSB-first from spi_data[55]; frame must be left-aligned.
  wire [55:0] spi_data     =
                             (chip_id == 8'h02) ? {ad9640_instr, is_read ? 8'h00 : wdata[7:0], 32'h0} :
                             (chip_id == 8'h03) ? {ad9117_frame, 40'h0} :
                             (chip_id == 8'h01) ? {si5340_frame, 40'h0} :
                             56'h0;

  wire        rd_en        = is_read && ((chip_id == 8'h02) ||
                             (chip_id == 8'h03) ||
                             ((chip_id == 8'h01) && (sub_idx == 2'd1)));

  assign spi_cmd = {slv_sel, 3'b000, rd_en, spi_data};  // 3+3+1+56=63 bits, matches [62:0]
  assign rd_byte = (chip_id == 8'h02) ? spi_rdata[39:32] : spi_rdata[47:40];
  
endmodule
