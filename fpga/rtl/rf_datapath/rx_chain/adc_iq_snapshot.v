`timescale 1ns / 1ps

// Dual-clock IQ snapshot buffer.
//
// Capture side runs at `i_adc_clk` (122.88 MHz on AD9640 DCOA, SI5340 OUT0) so
// samples are stored at the rx_chain's native rate without dropping anything
// to the async-FIFO read pinch (which only runs at sys_clk = 122.88 MHz).  The UART
// parser side stays at `i_sys_clk` — arm/done cross domains with standard
// 2-FF level synchronisers, and the BRAM is true dual-port (write @ adc_clk,
// read @ sys_clk) so the parser's read interface (i_rd_addr / i_chan_sel /
// o_rd_data) is unchanged from the old single-clock version.
//
// Sample-rate observed by the host = adc_clk / dec_ratio (122.88 MHz @ Dec=1x).
//
// Latency contract preserved:
//   * o_busy rises within ~3 sys_clks of i_arm (CDC + 1)
//   * o_done rises within ~3 sys_clks of the last captured sample
//   * o_rd_data settles 2 sys_clks after i_rd_addr changes
module adc_iq_snapshot #(
  parameter integer DEPTH = 16384
) (
  // sys_clk control / readback
  input  wire                i_sys_clk    ,
  input  wire                i_rst_n      ,
  input  wire                i_arm        ,
  input  wire [13:0]         i_n_samples  ,
  input  wire [13:0]         i_rd_addr    ,
  input  wire                i_chan_sel   ,
  output reg  [13:0]         o_rd_data    ,
  output wire                o_done       ,
  output wire                o_busy       ,
  // adc_clk capture
  input  wire                i_adc_clk    ,
  input  wire signed [13:0]  i_iq_i       ,
  input  wire signed [13:0]  i_iq_q       ,
  input  wire                i_iq_vld
);

  localparam [1:0] S_IDLE = 2'd0,
                   S_CAP  = 2'd1,
                   S_DONE = 2'd2;

  // ---- N latched on i_arm rising edge in sys_clk -----------------------
  // i_n_samples is set by the parser on the same edge it raises i_arm; we
  // latch it on the rising-edge and feed the adc_clk side a value that's
  // been stable for many cycles before the CDC'd arm even arrives.
  reg [13:0] n_sys_latched;
  reg        arm_sys_d;
  always @(posedge i_sys_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      n_sys_latched <= 14'd0;
      arm_sys_d     <= 1'b0;
    end else begin
      arm_sys_d <= i_arm;
      if (i_arm && !arm_sys_d) n_sys_latched <= i_n_samples;
    end
  end

  // ---- CDC: arm (sys → adc) -------------------------------------------
  (* ASYNC_REG = "TRUE" *) reg arm_adc_s0;
  (* ASYNC_REG = "TRUE" *) reg arm_adc_s1;
  always @(posedge i_adc_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      arm_adc_s0 <= 1'b0;
      arm_adc_s1 <= 1'b0;
    end else begin
      arm_adc_s0 <= i_arm;
      arm_adc_s1 <= arm_adc_s0;
    end
  end
  wire arm_adc = arm_adc_s1;

  // Snapshot N at the arm rising edge in adc domain (safe: n_sys_latched
  // has been stable for ≥ 2 adc_clks before arm_adc can rise).
  reg [13:0] n_adc;
  reg        arm_adc_d;
  always @(posedge i_adc_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      n_adc     <= 14'd0;
      arm_adc_d <= 1'b0;
    end else begin
      arm_adc_d <= arm_adc;
      if (arm_adc && !arm_adc_d) n_adc <= n_sys_latched;
    end
  end

  wire [14:0] n_cfg = (n_adc == 14'd0) ? 15'd16384 : {1'b0, n_adc};

  // ---- adc_clk capture FSM --------------------------------------------
  reg [1:0]  state_adc;
  reg [13:0] wr_addr;
  reg [14:0] left_cnt;
  reg        done_adc;
  reg        busy_adc;
  wire       cap_fire;

  (* ram_style = "block" *) reg [13:0] mem_i [0:DEPTH-1];
  (* ram_style = "block" *) reg [13:0] mem_q [0:DEPTH-1];
  assign cap_fire = (state_adc == S_CAP) && i_iq_vld;

  // Keep BRAM write port in a reset-free clocked process so Vivado can infer
  // true dual-port RAM (write @ i_adc_clk, read @ i_sys_clk).
  always @(posedge i_adc_clk) begin
    if (cap_fire) begin
      mem_i[wr_addr] <= i_iq_i;
      mem_q[wr_addr] <= i_iq_q;
    end
  end

  always @(posedge i_adc_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      state_adc <= S_IDLE;
      wr_addr   <= 14'd0;
      left_cnt  <= 15'd0;
      done_adc  <= 1'b0;
      busy_adc  <= 1'b0;
    end else begin
      if (!arm_adc) done_adc <= 1'b0;
      case (state_adc)
        S_IDLE: begin
          busy_adc <= 1'b0;
          if (arm_adc) begin
            state_adc <= S_CAP;
            wr_addr   <= 14'd0;
            left_cnt  <= n_cfg;
            busy_adc  <= 1'b1;
          end
        end
        S_CAP: begin
          if (!arm_adc) begin
            state_adc <= S_IDLE;
            busy_adc  <= 1'b0;
            done_adc  <= 1'b0;
          end else if (i_iq_vld) begin
            wr_addr <= wr_addr + 14'd1;
            if (left_cnt == 15'd1) begin
              state_adc <= S_DONE;
              busy_adc  <= 1'b0;
              done_adc  <= 1'b1;
            end
            left_cnt <= left_cnt - 15'd1;
          end
        end
        S_DONE: begin
          if (!arm_adc) state_adc <= S_IDLE;
        end
        default: state_adc <= S_IDLE;
      endcase
    end
  end

  // ---- CDC: done/busy (adc → sys) -------------------------------------
  (* ASYNC_REG = "TRUE" *) reg done_sys_s0;
  (* ASYNC_REG = "TRUE" *) reg done_sys_s1;
  (* ASYNC_REG = "TRUE" *) reg busy_sys_s0;
  (* ASYNC_REG = "TRUE" *) reg busy_sys_s1;
  always @(posedge i_sys_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      done_sys_s0 <= 1'b0; done_sys_s1 <= 1'b0;
      busy_sys_s0 <= 1'b0; busy_sys_s1 <= 1'b0;
    end else begin
      done_sys_s0 <= done_adc; done_sys_s1 <= done_sys_s0;
      busy_sys_s0 <= busy_adc; busy_sys_s1 <= busy_sys_s0;
    end
  end
  assign o_done = done_sys_s1;
  assign o_busy = busy_sys_s1;

  // ---- sys_clk read port (dual-port BRAM) -----------------------------
  reg [13:0] rd_i_data;
  reg [13:0] rd_q_data;
  always @(posedge i_sys_clk) begin
    rd_i_data <= mem_i[i_rd_addr];
    rd_q_data <= mem_q[i_rd_addr];
    o_rd_data <= i_chan_sel ? rd_q_data : rd_i_data;
  end

endmodule
