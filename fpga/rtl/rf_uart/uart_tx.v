// 8N1 UART transmitter, fixed 4-byte burst helper.
module uart_tx #(
  parameter integer CLK_HZ = 50_000_000,
  parameter integer BAUD   = 921_600
  )
  (
  input  wire       clk  ,
  input  wire       rst_n,
  input  wire       start,
  input  wire [7:0] data0,
  input  wire [7:0] data1,
  input  wire [7:0] data2,
  input  wire [7:0] data3,
  output reg        busy ,
  output reg        tx
  );


  localparam integer BIT_CLK = CLK_HZ / BAUD;

  localparam [1:0] S_IDLE  = 2'd0,
                   S_START = 2'd1,
                   S_DATA  = 2'd2,
                   S_STOP  = 2'd3;

  reg  [1:0] state   ;
  reg [15:0] cnt     ;
  reg  [2:0] bit_idx ;
  reg  [1:0] byte_idx;
  reg  [7:0] sh      ;

  function [7:0] pick_byte;
  input [1:0] idx;
    begin
      case (idx)
        2'd0   : pick_byte = data0;
        2'd1   : pick_byte = data1;
        2'd2   : pick_byte = data2;
        default: pick_byte = data3;
      endcase
    end
  endfunction

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state    <= S_IDLE;
      cnt      <= 0;
      bit_idx  <= 0;
      byte_idx <= 0;
      sh       <= 8'h00;
      busy     <= 1'b0;
      tx       <= 1'b1;
    end else begin
      case (state)
        S_IDLE: begin
          tx <= 1'b1;
          if (start) begin
            busy     <= 1'b1;
            byte_idx <= 2'd0;
            sh       <= pick_byte(2'd0);
            cnt      <= BIT_CLK - 1;
            state    <= S_START;
          end else
          busy     <= 1'b0;
        end
        S_START: begin
          tx <= 1'b0;
          if (cnt == 0) begin
            cnt     <= BIT_CLK - 1;
            bit_idx <= 3'd0;
            state   <= S_DATA;
          end else
          cnt     <= cnt - 1;
        end
        S_DATA: begin
          tx <= sh[bit_idx];
          if (cnt == 0) begin
            cnt     <= BIT_CLK - 1;
            if (bit_idx == 3'd7)
            state   <= S_STOP;
            else
            bit_idx <= bit_idx + 1'b1;
          end else
          cnt     <= cnt - 1;
        end
        S_STOP: begin
          tx <= 1'b1;
          if (cnt == 0) begin
            if (byte_idx == 2'd3) begin
              busy     <= 1'b0;
              state    <= S_IDLE;
            end else begin
              byte_idx <= byte_idx + 1'b1;
              sh       <= pick_byte(byte_idx + 1'b1);
              cnt      <= BIT_CLK - 1;
              state    <= S_START;
            end
          end else
          cnt      <= cnt - 1;
        end
        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
