`timescale 1ns / 1ps

module adc_iq_stream_drain #(
  parameter integer FIFO_DEPTH = 256
) (
  input  wire                i_clk        ,
  input  wire                i_rst_n      ,
  input  wire                i_enable     ,
  input  wire signed [13:0]  i_iq_i       ,
  input  wire signed [13:0]  i_iq_q       ,
  input  wire                i_iq_vld     ,
  output wire [7:0]          o_byte       ,
  output wire                o_byte_vld   ,
  input  wire                i_byte_ready ,
  output reg                 o_overflow
);

  localparam integer PTR_W = 8;
  reg [PTR_W-1:0] wr_ptr;
  reg [PTR_W-1:0] rd_ptr;
  reg [PTR_W:0]   count;

  wire pop_en    = i_enable && i_byte_ready && (count != 0);
  wire push_req  = i_enable && i_iq_vld;
  wire can_push4 = (count <= FIFO_DEPTH-4);

  assign o_byte_vld = (count != 0);

  // Pointer / occupancy / overflow flop with async reset.
  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      wr_ptr     <= {PTR_W{1'b0}};
      rd_ptr     <= {PTR_W{1'b0}};
      count      <= {(PTR_W+1){1'b0}};
      o_overflow <= 1'b0;
    end else if (!i_enable) begin
      wr_ptr     <= {PTR_W{1'b0}};
      rd_ptr     <= {PTR_W{1'b0}};
      count      <= {(PTR_W+1){1'b0}};
      o_overflow <= 1'b0;
    end else begin
      // Apply pop and push in one place so count tracks net occupancy change:
      //   pop only   -> -1
      //   push only  -> +4
      //   both       -> +3
      if (pop_en)
        rd_ptr <= rd_ptr + 1'b1;

      if (push_req && can_push4)
        wr_ptr <= wr_ptr + 3'd4;
      else if (push_req && !can_push4)
        o_overflow <= 1'b1;

      case ({push_req && can_push4, pop_en})
        2'b10: count <= count + 3'd4;
        2'b01: count <= count - 1'b1;
        2'b11: count <= count + 3'd3;
        default: count <= count;
      endcase
    end
  end

  // FIFO memory write — separate clock-only always block so Vivado can infer
  // distributed RAM (LUTRAM) instead of pure flip-flops.  No reset on memory
  // bits: pointers are reset and the empty/count guards prevent reading stale
  // data, so explicit clearing is unnecessary.  Without this split, Synth
  // 8-7137 fires (Set+Reset same priority) and Synth 8-4767 denies RAM
  // inference, blowing the design up into hundreds of FFs.
  (* ram_style = "distributed" *) reg [7:0] fifo_mem [0:FIFO_DEPTH-1];
  always @(posedge i_clk) begin
    if (i_rst_n && i_enable && push_req && can_push4) begin
      fifo_mem[wr_ptr]        <= i_iq_i[13:6];
      fifo_mem[wr_ptr + 1'b1] <= {2'b00, i_iq_i[5:0]};
      fifo_mem[wr_ptr + 2'd2] <= i_iq_q[13:6];
      fifo_mem[wr_ptr + 2'd3] <= {2'b00, i_iq_q[5:0]};
    end
  end

  assign o_byte = fifo_mem[rd_ptr];

endmodule
