// 8N1 UART transmitter, single-byte streaming variant.
// Pulse `start` high for one cycle with `data` valid; module asserts `busy`
// until the stop bit completes, then drops it. Drive `start` low again before
// `busy` falls to avoid retriggering on the same byte.
module uart_tx_byte #(
  parameter integer CLK_HZ = 50_000_000,
  parameter integer BAUD   = 921_600
  )
  (
  input  wire       clk  ,
  input  wire       rst_n,
  input  wire       start,
  input  wire [7:0] data ,
  output reg        busy ,
  output reg        tx
  );

  localparam integer BIT_CLK = CLK_HZ / BAUD;

  localparam [1:0] S_IDLE  = 2'd0,
                   S_START = 2'd1,
                   S_DATA  = 2'd2,
                   S_STOP  = 2'd3;

  reg  [1:0] state  ;
  reg [15:0] cnt    ;
  reg  [2:0] bit_idx;
  reg  [7:0] sh     ;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state   <= S_IDLE;
      cnt     <= 0;
      bit_idx <= 0;
      sh      <= 8'h00;
      busy    <= 1'b0;
      tx      <= 1'b1;
    end else begin
      case (state)
        S_IDLE: begin
          tx <= 1'b1;
          if (start) begin
            busy  <= 1'b1;
            sh    <= data;
            cnt   <= BIT_CLK - 1;
            state <= S_START;
          end else
            busy <= 1'b0;
        end
        S_START: begin
          tx <= 1'b0;
          if (cnt == 0) begin
            cnt     <= BIT_CLK - 1;
            bit_idx <= 3'd0;
            state   <= S_DATA;
          end else
            cnt <= cnt - 1;
        end
        S_DATA: begin
          tx <= sh[bit_idx];
          if (cnt == 0) begin
            cnt <= BIT_CLK - 1;
            if (bit_idx == 3'd7)
              state <= S_STOP;
            else
              bit_idx <= bit_idx + 1'b1;
          end else
            cnt <= cnt - 1;
        end
        S_STOP: begin
          tx <= 1'b1;
          if (cnt == 0) begin
            busy  <= 1'b0;
            state <= S_IDLE;
          end else
            cnt <= cnt - 1;
        end
        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
