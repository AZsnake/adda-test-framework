// boot_fsm — walks the boot ROM, issues SPI writes to SI5340 / AD9640 / AD9117.
//
// Entry decode (matches fpga/scripts/cbpro_to_mem.py):
//   [31:28] opcode  0=WRITE, 1=DELAY, 2=WAIT_LOL, 0xF=EOF
//   [27:24] chip    1=SI5340, 2=AD9640, 3=AD9117 (same as UART chip ID)
//   [23:16] page    SI5340 only; 0 for AD9640/AD9117
//   [15: 8] addr    register address low byte (DELAY: index into delay table)
//   [ 7: 0] data    register data
//
// SI5340 page tracking: when a WRITE crosses to a new page, FSM auto-emits a
// 2-frame "PAGE_SEL write" (write reg[0x01]=page) BEFORE the actual write,
// then performs the original write (also 2 frames).  Total: up to 4 SPI frames
// per ROM entry for SI5340; 1 frame for AD9640/AD9117.
//
// Delay table (cycles count derived from CLK_HZ):
//   index 0 = 300 ms (SI5340 PLL calibration after preamble)
//   index 1 = 10  ms (chip POR settle / general)
//
// Status:
//   o_busy  high while booting (gates rf_ctrl_path SPI mux & UART parser)
//   o_done  one-cycle pulse on FINISHED
//   o_chip  current chip ID being configured (0 when idle/finished)
//   o_err   non-zero on failure (0x10 = SI5340 LOL timeout)

module boot_fsm #(
  parameter integer CLK_HZ        = 19_200_000,
  parameter integer ROM_DEPTH     = 512,
  parameter integer POR_DELAY_MS  = 10 ,
  parameter integer DELAY0_MS     = 300,
  parameter integer DELAY1_MS     = 10 ,
  parameter integer LOL_TIMEOUT_MS= 1000  // SI5340 lock can take ~500 ms on low-Fpfd configs
) (
  input  wire        clk            ,
  input  wire        rst_n          ,
  input  wire        i_start        , // 1-cycle pulse to restart boot (UART 0x20)
  input  wire        i_si5340_lolb  , // PLL lock indicator (1 = locked)

  // ROM interface (synchronous read; data available one cycle after addr)
  output reg  [$clog2(ROM_DEPTH)-1:0] o_rom_addr,
  input  wire [31:0]                  i_rom_data,

  // SPI master interface (drives rf_ctrl_path mux; highest priority)
  output reg         o_spi_valid    ,
  output wire [62:0] o_spi_cmd      ,
  input  wire        i_spi_done     ,

  // Status
  output wire        o_busy         ,
  output reg         o_done         , // 1-cycle pulse
  output reg         o_done_sticky  ,
  output wire [3:0]  o_chip         ,
  output reg  [7:0]  o_err
);

  // ----- Cycle counts ------------------------------------------------------
  localparam integer CYC_PER_MS  = CLK_HZ / 1000;
  localparam integer POR_CYC     = POR_DELAY_MS   * CYC_PER_MS;
  localparam integer DELAY0_CYC  = DELAY0_MS      * CYC_PER_MS;
  localparam integer DELAY1_CYC  = DELAY1_MS      * CYC_PER_MS;
  localparam integer LOL_TO_CYC  = LOL_TIMEOUT_MS * CYC_PER_MS;

  // ----- Opcode constants --------------------------------------------------
  localparam [3:0] OP_WRITE = 4'h0;
  localparam [3:0] OP_DELAY = 4'h1;
  localparam [3:0] OP_WLOL  = 4'h2;
  localparam [3:0] OP_EOF   = 4'hF;

  // ----- State -------------------------------------------------------------
  localparam [3:0] S_IDLE       = 4'd0,
                   S_POR        = 4'd1,
                   S_FETCH      = 4'd2,
                   S_DECODE     = 4'd3,
                   S_PAGE_F0    = 4'd4,  // SI5340 PAGE_SEL set-addr (sub_idx=0)
                   S_PAGE_F1    = 4'd5,  // SI5340 PAGE_SEL write    (sub_idx=1)
                   S_WRITE_F0   = 4'd6,  // payload write: SI5340 set-addr or single-frame chip
                   S_WRITE_F1   = 4'd7,  // SI5340 write-data
                   S_DELAY      = 4'd8,
                   S_WAIT_LOL   = 4'd9,
                   S_FINISHED   = 4'd10,
                   S_DONE_LATCH = 4'd11; // one cycle after o_done pulse: commit o_done_sticky

  reg [3:0] state;

  // ----- Entry decode (combinational on i_rom_data) -----------------------
  wire [3:0] e_op   = i_rom_data[31:28];
  wire [3:0] e_chip = i_rom_data[27:24];
  wire [7:0] e_page = i_rom_data[23:16];
  wire [7:0] e_addr = i_rom_data[15: 8];
  wire [7:0] e_data = i_rom_data[ 7: 0];

  // Latched current entry (so we don't re-decode while ROM addr changes)
  reg [3:0]  cur_chip;
  reg [7:0]  cur_page, cur_addr, cur_data;

  // SI5340 page tracker — reset to 0xFF so the very first SI5340 write forces
  // a PAGE_SEL (chip POR comes up on an unknown page; safer to set it).
  reg [7:0] si5340_page;
  wire      need_page_set = (cur_chip == 4'h1) && (cur_page != si5340_page);

  // ----- Counters ----------------------------------------------------------
  reg [31:0] cnt;

  // ----- Start trigger / busy ---------------------------------------------
  assign o_busy = (state != S_IDLE) && (state != S_FINISHED) && (state != S_DONE_LATCH);
  assign o_chip = o_busy ? cur_chip : 4'h0;

  // ----- SPI command packing (reuse uart_spi_pack) ------------------------
  // The packer expects 8-bit chip_id matching UART convention; our chip nibble
  // now uses the same encoding (1/2/3), so zero-extend.
  reg [7:0] pk_chip;
  reg [7:0] pk_addr;
  reg [7:0] pk_data;
  reg [1:0] pk_sub;
  wire [1:0] pk_frames;

  uart_spi_pack u_pack (
    .chip_id   (pk_chip),
    .cmd       (8'h01)     ,   // boot only writes
    .addr      (pk_addr)   ,
    .wdata     (pk_data)   ,
    .sub_idx   (pk_sub)    ,
    .spi_rdata (56'h0)     ,
    .spi_cmd   (o_spi_cmd) ,
    .frame_cnt (pk_frames) ,
    .bad_chip  (         ) ,
    .rd_byte   (         )
  );

  // ----- Main FSM ---------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state         <= S_POR;
      o_rom_addr    <= 0;
      o_spi_valid   <= 1'b0;
      o_done        <= 1'b0;
      o_done_sticky <= 1'b0;
      o_err         <= 8'h00;
      cur_chip      <= 4'h0;
      cur_page      <= 8'h0; cur_addr <= 8'h0; cur_data <= 8'h0;
      si5340_page   <= 8'hFF;
      cnt           <= POR_CYC[31:0];  // arm POR delay for the initial auto-boot
      pk_chip       <= 8'h00; pk_addr <= 8'h00; pk_data <= 8'h00; pk_sub <= 2'd0;
    end else if (i_start) begin
      // Re-trigger from ANY state (0x20 retry; 0xF2-driven boot reset).
      // Aborts in-flight SPI; the priority mux blocks SPI core during S_POR
      // so a dangling spi_done has nothing to update here.
      state         <= S_POR;
      o_rom_addr    <= 0;
      si5340_page   <= 8'hFF;
      o_err         <= 8'h00;
      o_done_sticky <= 1'b0;
      o_spi_valid   <= 1'b0;
      cnt           <= POR_CYC[31:0];
    end else begin
      o_spi_valid <= 1'b0;
      o_done      <= 1'b0;

      case (state)
        // ---- IDLE: wait for restart ------------------------------------
        S_IDLE: begin
          // i_start handled above; nothing else to do
        end

        // ---- POR delay before first SPI --------------------------------
        S_POR: begin
          if (cnt == 32'd0) begin
            o_rom_addr <= 0;
            state      <= S_FETCH;
          end else begin
            cnt <= cnt - 1'b1;
          end
        end

        // ---- FETCH: ROM addr is set; data valid next cycle -------------
        S_FETCH: begin
          state <= S_DECODE;
        end

        // ---- DECODE: latch current entry, dispatch ---------------------
        S_DECODE: begin
          cur_chip <= e_chip;
          cur_page <= e_page;
          cur_addr <= e_addr;
          cur_data <= e_data;

          case (e_op)
            OP_WRITE: begin
              if ((e_chip == 4'h1) && (e_page != si5340_page)) begin
                // SI5340 cross-page → emit PAGE_SEL (reg 0x01 = page) first
                pk_chip   <= 8'h01;
                pk_addr   <= 8'h01;
                pk_data   <= e_page;
                pk_sub    <= 2'd0;
                o_spi_valid <= 1'b1;
                state     <= S_PAGE_F0;
              end else begin
                pk_chip   <= {4'h0, e_chip};
                pk_addr   <= e_addr;
                pk_data   <= e_data;
                pk_sub    <= 2'd0;
                o_spi_valid <= 1'b1;
                state     <= S_WRITE_F0;
              end
            end
            OP_DELAY: begin
              cnt   <= (e_data == 8'h00) ? DELAY0_CYC[31:0] : DELAY1_CYC[31:0];
              state <= S_DELAY;
            end
            OP_WLOL: begin
              cnt   <= LOL_TO_CYC[31:0];
              state <= S_WAIT_LOL;
            end
            OP_EOF: begin
              // boot_rom.mem from --concat collapses inter-chip EOFs into a
              // single trailing one; first EOF = end of boot.
              state <= S_FINISHED;
            end
            default: begin
              // Unknown opcode → treat as no-op, advance
              o_rom_addr <= o_rom_addr + 1'b1;
              state      <= S_FETCH;
            end
          endcase
        end

        // ---- SI5340 PAGE_SEL: two SPI frames, then fall into write ----
        S_PAGE_F0: begin
          if (i_spi_done) begin
            pk_sub      <= 2'd1;
            o_spi_valid <= 1'b1;
            state       <= S_PAGE_F1;
          end
        end
        S_PAGE_F1: begin
          if (i_spi_done) begin
            si5340_page <= cur_page;
            // Now issue the actual register write that triggered the page change
            pk_chip     <= 8'h01;
            pk_addr     <= cur_addr;
            pk_data     <= cur_data;
            pk_sub      <= 2'd0;
            o_spi_valid <= 1'b1;
            state       <= S_WRITE_F0;
          end
        end

        // ---- WRITE: 1 frame (AD9640/AD9117) or 2 frames (SI5340) ------
        S_WRITE_F0: begin
          if (i_spi_done) begin
            if (cur_chip == 4'h1) begin
              // SI5340 needs second frame (40 | wdata)
              pk_sub      <= 2'd1;
              o_spi_valid <= 1'b1;
              state       <= S_WRITE_F1;
            end else begin
              o_rom_addr <= o_rom_addr + 1'b1;
              state      <= S_FETCH;
            end
          end
        end
        S_WRITE_F1: begin
          if (i_spi_done) begin
            o_rom_addr <= o_rom_addr + 1'b1;
            state      <= S_FETCH;
          end
        end

        // ---- DELAY --------------------------------------------------
        S_DELAY: begin
          if (cnt == 32'd0) begin
            o_rom_addr <= o_rom_addr + 1'b1;
            state      <= S_FETCH;
          end else begin
            cnt <= cnt - 1'b1;
          end
        end

        // ---- WAIT_LOL: poll lolb; timeout → set err and continue ---
        S_WAIT_LOL: begin
          if (i_si5340_lolb) begin
            o_rom_addr <= o_rom_addr + 1'b1;
            state      <= S_FETCH;
          end else if (cnt == 32'd0) begin
            o_err      <= 8'h10;  // SI5340 lock failed
            o_rom_addr <= o_rom_addr + 1'b1;
            state      <= S_FETCH;
          end else begin
            cnt <= cnt - 1'b1;
          end
        end

        // ---- FINISHED: pulse o_done; sticky committed next cycle ---
        // Splitting into two cycles ensures saw_done_pulse (captured by
        // posedge o_done) is set before wait(done_sticky) unblocks.
        S_FINISHED: begin
          o_done <= 1'b1;
          state  <= S_DONE_LATCH;
        end

        // ---- DONE_LATCH: assert o_done_sticky one cycle after pulse -
        S_DONE_LATCH: begin
          o_done_sticky <= 1'b1;
          state         <= S_IDLE;
        end

        default: state <= S_FINISHED;
      endcase
    end
  end

endmodule
