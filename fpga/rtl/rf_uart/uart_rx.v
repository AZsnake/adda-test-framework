// 8N1 UART receiver, one byte per frame.
module uart_rx #(
  parameter integer CLK_HZ = 50_000_000,
  parameter integer BAUD   = 921_600
  )
  (
  input  wire       clk  ,
  input  wire       rst_n,
  input  wire       rx   ,
  output reg  [7:0] data ,
  output reg        valid
  );


  localparam integer BIT_CLK = CLK_HZ / BAUD;

  localparam [1:0] S_IDLE = 2'd0,
                   S_DATA = 2'd1,
                   S_STOP = 2'd2;
                               
  reg  [1:0] state  ;
  reg [15:0] cnt    ;
  reg  [2:0] bit_idx;

  // 2-FF synchroniser on the async rx pin.  Without this, metastability on the
  // raw pad can cause the start-bit edge detector and the data sampler to see
  // different values in the same cycle, producing intermittent dropped/extra
  // bytes (symptom: random FPGA status=0x01/0x02 mid-transfer).
  (* ASYNC_REG = "TRUE" *) reg rx_sync0;
  (* ASYNC_REG = "TRUE" *) reg rx_sync1;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_sync0 <= 1'b1;
      rx_sync1 <= 1'b1;
    end else begin
      rx_sync0 <= rx;
      rx_sync1 <= rx_sync0;
    end
  end
  wire rx_s = rx_sync1;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state   <= S_IDLE;
      cnt     <= 0;
      bit_idx <= 0;
      data    <= 8'h00;
      valid   <= 1'b0;
    end else begin
      valid   <= 1'b0;
      case (state)
        S_IDLE: begin
          if (!rx_s) begin
            cnt     <= BIT_CLK + BIT_CLK / 2;  // 1.5 bit periods → sample at center of first data bit
            state   <= S_DATA;
            bit_idx <= 3'd0;
          end
        end
        S_DATA: begin
          if (cnt != 0)
          cnt           <= cnt - 1;
          else begin
            data[bit_idx] <= rx_s;
            cnt           <= BIT_CLK - 1;
            if (bit_idx == 3'd7)
            state         <= S_STOP;
            else
            bit_idx       <= bit_idx + 1'b1;
          end
        end
        S_STOP: begin
          if (cnt != 0)
          cnt     <= cnt - 1;
          else begin
            valid   <= 1'b1;
            state   <= S_IDLE;
          end
        end
        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
