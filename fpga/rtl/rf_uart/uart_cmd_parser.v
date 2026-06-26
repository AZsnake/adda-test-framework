// UART command parser: 5-byte command in (+N for burst), 4-byte ACK out, SPI via rf_spi_core.
// Supported commands (see docs/uart_command_protocol.md):
//   0x01 write, 0x02 read, 0x03 burst-write (N bytes), 0x10 soft-reset, 0x11 output-enable,
//   0x12 power-down, 0x20 boot-trigger, 0x21 boot-status, 0x30 ADC arm, 0x31 ADC read hi,
//   0x32 ADC read lo, 0x33 ADC burst-read (streams 2*N raw bytes then 4-byte ACK),
//   0x34 ADC streaming read: data field is 14-bit sample count. N>0 → bounded
//        burst (N*4 bytes + ACK). N==0 → continuous: stream forever, terminated
//        when the host sends ANY byte (then FPGA finishes current 4-byte sample
//        and emits the 4-byte ACK).
//   0x40 DAC tone enable, 0x41 DAC wave/hb_bypass, 0x42 DAC freq word, 0x43 DAC amplitude,
//   0x44 NCO freq word (digital DDC), 0x45 RX config (dec/mode/iq/fir),
//   0x46~0x49 IQ balance, 0x4A DCLKIO phase-shift target (16-bit hi/lo split),
//   0xF0 ping, 0xF1 firmware version, 0xF2 global reset,
//   0xFE last-error query.
// For 0x31/0x32/0x33, f_addr[6] selects ADC channel: 0=I (channel A), 1=Q (channel B).
// f_addr[5:0] + f_data still carry the 14-bit BRAM address (or are ignored for 0x33).
// Status codes: 0x00 OK, 0x01 unknown cmd, 0x02 bad chip ID, 0x05 boot/adc busy.
module uart_cmd_parser #(
  parameter integer CLK_HZ     = 50_000_000,
  parameter [7:0]   FW_VERSION = 8'h01
  )
  (
  input  wire        clk      ,
  input  wire        rst_n    ,
  input  wire        uart_rx  ,
  output reg         uart_tx  ,

  output reg         spi_valid,
  output wire [62:0] spi_cmd  ,
  input  wire        spi_done ,
  input  wire [55:0] spi_rdata,
  output wire        spi_busy ,

  output reg         o_global_rst,
  output reg         o_boot_start,    // 1-cycle pulse on accepted 0x20

  // Boot status (from boot_fsm) — used by 0x20/0x21 decode and to gate SPI cmds.
  input  wire        i_boot_busy ,
  input  wire        i_boot_done ,    // sticky after first completion
  input  wire [3:0]  i_boot_chip ,    // chip currently being configured (0 idle)
  input  wire [7:0]  i_boot_err  ,    // 0x00 ok, 0x10 SI5340 LOL timeout

  // SI5340 status pins — surfaced in 0x21 reply for diagnostics
  input  wire        i_si5340_lolb ,  // 1 = PLL locked
  input  wire        i_si5340_losxb,  // 1 = input clock OK

  // ADC snapshot control (to/from adc_iq_snapshot)
  output reg         o_adc_arm    ,   // level: held high while waiting for capture done
  output reg  [13:0] o_adc_n      ,   // sample count for 0x30 (1..16384, 0→16384)
  output reg  [13:0] o_adc_rd_addr,   // BRAM read address for 0x31 (0..16383)
  output reg         o_adc_chan_sel,  // 0=I/channel A, 1=Q/channel B (sticky during burst)
  input  wire        i_adc_done   ,   // level from adc_capture (high until o_adc_arm low)
  input  wire        i_adc_busy   ,   // level: adc_capture is running
  input  wire [13:0] i_adc_rdata  ,   // 14-bit BRAM read data — already muxed by chan_sel upstream

  // DAC waveform control (0x40~0x43) — sticky config, cleared to defaults by reset / 0xF2
  output reg         o_dac_tone_en,
  output reg  [2:0]  o_dac_wave_sel,
  output reg         o_dac_hb_bypass,  // 0x41 bit[7]: 1 = skip TX halfband interp
  output reg  [15:0] o_dac_freq_word,
  output reg  [7:0]  o_dac_amp_pct,

  // DCLKIO dynamic phase-shift target (0x4A, 16-bit hi/lo split) — sticky.
  // Absolute PS step position seeked by dac_dclk_ps_ctrl. 0 = nominal phase.
  output reg  [15:0] o_dac_dclk_ps_target,

  // Digital DDC/RX control — sticky, cleared by reset / 0xF2
  output reg  [15:0] o_nco_freq_word,
  output reg  [1:0]  o_dec_ratio    ,
  output reg         o_capture_mode ,
  output reg         o_iq_bypass    ,
  output reg         o_fir_bypass   ,
  output reg  [1:0]  o_fir_sel      ,  // RX FIR coefficient bank (0..3), 0x45 bit[6:5]
  output reg  [15:0] o_iq_mult_op1  ,
  output reg  [15:0] o_iq_mult_op2  ,
  output reg  [13:0] o_iq_offset_i  ,
  output reg  [13:0] o_iq_offset_q  ,

  input  wire [7:0]  i_stream_byte  ,
  input  wire        i_stream_byte_vld,
  input  wire        i_stream_overflow,
  output reg         o_stream_enable ,
  output reg         o_stream_byte_ready,

  // Waveform player control (0x50/0x51/0x52) — sticky config + URAM write port.
  // o_wave_play_en latched: 0=tone_gen on the output, 1=wave_player on output.
  // o_wave_wr_en pulses one cycle per 32-bit URAM word during 0x50 load.
  output reg         o_wave_play_en  ,
  output reg  [17:0] o_wave_loop_len_minus1,
  output reg         o_wave_swap_iq  ,
  output reg         o_wave_neg_q    ,
  output reg         o_wave_wr_en    ,
  output reg  [17:0] o_wave_wr_addr  ,
  output reg  [31:0] o_wave_wr_data  ,

  output wire [2:0]  o_state,
  output wire        o_frame_start,
  output wire [7:0]  o_last_chip,
  output wire [7:0]  o_last_cmd,
  output wire [7:0]  o_last_status
  );


  localparam [3:0] ST_IDLE        = 4'd0,
                   ST_CMD         = 4'd1,
                   ST_CHIP        = 4'd2,
                   ST_ADDR        = 4'd3,
                   ST_DATA        = 4'd4,
                   ST_WAIT_SPI    = 4'd5,
                   ST_SEND_ACK    = 4'd6,
                   ST_BURST_RX    = 4'd7,
                   ST_BURST_SPI   = 4'd8,
                   ST_ADC_WAIT    = 4'd9,  // waiting for adc_capture done (0x30)
                   ST_ADC_RD      = 4'd10, // waiting 1 cycle for BRAM read latency (0x31/0x32)
                   ST_ADC_BURST   = 4'd11, // 0x33 burst stream: 2N bytes raw + ACK trailer
                   ST_ADC_STREAM  = 4'd12, // 0x34 stream via adc_iq_stream_drain
                   ST_WAVE_RX     = 4'd13, // 0x50 waveform chunk load (1024 bytes -> 256 IQ words)
                   ST_ADC_REARM   = 4'd14; // 0x30: drop arm until prior capture aborts
  // o_state = state[2:0]; ST_SEND_ACK=6 triggers led_status ACK effect.
  // ST_ADC_WAIT=9 → 3'd1, ST_ADC_RD=10 → 3'd2, ST_ADC_BURST=11 → 3'd3 — safe aliasing.

  reg  [3:0] state                              ;
  reg  [7:0] f_cmd, f_chip, f_addr, f_data      ;
  reg  [7:0] eff_cmd, eff_addr, eff_data        ; // drives uart_spi_pack inputs
  reg  [7:0] ack_st, ack_data                   ;
  reg  [7:0] last_chip, last_cmd, last_status   ;
  reg  [7:0] err_reg                            ;
  reg  [1:0] sub_idx                            ; // chip-level SPI sub-frame (SI5340 = 2)
  reg  [1:0] frame_cnt_l                        ; // latched chip-frame count
  reg  [1:0] macro_idx                          ; // logical sub-write (0x10 = 2 steps)
  reg  [1:0] macro_n                            ;
  reg  [7:0] burst_n, burst_idx                 ;
  reg        active                             ;
  reg        adc_seen_busy                      ; // 0x30: saw i_adc_busy before accepting done
  // Abort 0x30 if adc_clk / rx_chain never delivers samples (otherwise parser
  // stays in ST_ADC_WAIT forever and ignores all further UART, including Ping).
  localparam integer ADC_WAIT_TIMEOUT_CYC = CLK_HZ / 10;  // 100 ms @ CLK_HZ
  reg [31:0] adc_wait_cnt;

  // 0x33 ADC burst-read streaming state
  reg [13:0] adc_bidx                           ; // current sample index 0..N-1
  reg  [2:0] adc_bphase                         ; // 0=set addr, 1=BRAM valid+latch, 2=tx hi, 3=tx lo, 4=advance
  reg  [7:0] adc_bxor                           ; // XOR8 over streamed payload
  reg [13:0] adc_bsample                        ; // latched sample

  // 0x50 waveform chunk-load state: fixed 1024 bytes per command =
  // 256 IQ words.  Byte order on the wire is LE: I_lo, I_hi, Q_lo, Q_hi.
  reg [9:0]  wave_byte_idx                      ; // 0..1023, counts received bytes
  reg [7:0]  wave_acc0, wave_acc1, wave_acc2    ; // shift register for partial IQ word
  reg [17:0] wave_wr_addr_r                     ; // current URAM write address
  reg        burst_tx_start                     ; // 1-cycle pulse to uart_tx_byte
  reg  [7:0] burst_tx_data                      ;
  reg        burst_active                       ; // routes uart_tx to streaming tx
  reg [15:0] stream_target_bytes                ; // 0 = continuous mode (stop on rx_valid)
  reg [15:0] stream_sent_bytes                  ;
  reg [7:0]  stream_xor                         ;
  reg        stream_stop_req                    ; // latched in continuous mode on any UART RX byte
  reg        ack_started                        ; // one-cycle start strobe already issued
  reg        ack_seen_busy                      ; // uart_tx has entered busy for this ACK

  wire [7:0] rx_data ;
  wire       rx_valid;

  wire [62:0] pack_cmd   ;
  wire  [1:0] pack_frames;
  wire        pack_bad   ;
  wire  [7:0] pack_rd    ;

  uart_rx #(.CLK_HZ(CLK_HZ)) u_rx (
    .clk   (clk),
    .rst_n (rst_n),
    .rx    (uart_rx),
    .data  (rx_data),
    .valid (rx_valid)
  );

  uart_spi_pack u_pack (
    .chip_id   (f_chip),
    .cmd       (eff_cmd),
    .addr      (eff_addr),
    .wdata     (eff_data),
    .sub_idx   (sub_idx),
    .spi_rdata (spi_rdata),
    .spi_cmd   (pack_cmd),
    .frame_cnt (pack_frames),
    .bad_chip  (pack_bad),
    .rd_byte   (pack_rd)
  );

  assign spi_cmd        = pack_cmd;
  assign spi_busy       = active;
  assign o_state        = state[2:0];
  assign o_frame_start  = (state == ST_IDLE) && rx_valid && (rx_data == 8'haa);
  assign o_last_chip    = last_chip;
  assign o_last_cmd     = last_cmd;
  assign o_last_status  = last_status;

  wire       tx_start = (state == ST_SEND_ACK) && !ack_seen_busy && !ack_started;
  wire [7:0] ack_ck   = 8'hbb ^ ack_st ^ ack_data;

wire tx_main_line, tx_stream_line, tx_stream_busy, tx_main_busy;

  uart_tx #(.CLK_HZ(CLK_HZ)) u_tx (
    .clk   (clk),
    .rst_n (rst_n),
    .start (tx_start),
    .data0 (8'hbb),
    .data1 (ack_st),
    .data2 (ack_data),
    .data3 (ack_ck),
    .busy  (tx_main_busy),
    .tx    (tx_main_line)
  );

  uart_tx_byte #(.CLK_HZ(CLK_HZ)) u_tx_byte (
    .clk   (clk),
    .rst_n (rst_n),
    .start (burst_tx_start),
    .data  (burst_tx_data),
    .busy  (tx_stream_busy),
    .tx    (tx_stream_line)
  );

  // Both tx modules idle-high; mux is glitch-safe as long as the inactive one
  // is in S_IDLE.  Register the muxed result so the final FF directly drives
  // the top-level port and can be packed into the IOB (XDC: IOB TRUE on
  // o_uart_tx).  Adds 1 sys_clk (~8 ns) of latency, irrelevant vs. 8.68 µs/bit.
  wire uart_tx_mux = burst_active ? tx_stream_line : tx_main_line;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) uart_tx <= 1'b1;     // UART idle-high
    else        uart_tx <= uart_tx_mux;
  end

  // 0x34 completion condition: bounded burst hit its target, OR continuous mode
  // received a host stop byte and the next byte would start a new 4-byte sample.
  wire stream_bounded_done   = (stream_target_bytes != 16'd0) &&
                               (stream_sent_bytes  >= stream_target_bytes);
  wire stream_continuous_done = (stream_target_bytes == 16'd0) && stream_stop_req &&
                                (stream_sent_bytes[1:0] == 2'b00);
  wire stream_done = stream_bounded_done || stream_continuous_done;

  // ----- command classification ---------------------------------------------
  wire is_reg       = (f_cmd == 8'h01) || (f_cmd == 8'h02);
  wire is_burst     = (f_cmd == 8'h03);
  wire is_chip_ctrl = (f_cmd == 8'h10) || (f_cmd == 8'h11) || (f_cmd == 8'h12);
  wire is_init      = (f_cmd == 8'h20) || (f_cmd == 8'h21);
  wire is_adc       = (f_cmd == 8'h30) || (f_cmd == 8'h31) ||
                      (f_cmd == 8'h32) || (f_cmd == 8'h33) ||
                      (f_cmd == 8'h34);
  wire is_dac_tone  = (f_cmd == 8'h40);
  wire is_dac_cfg   = (f_cmd == 8'h41) || (f_cmd == 8'h42) || (f_cmd == 8'h43);
  wire is_dac_cmd   = is_dac_tone || is_dac_cfg;
  wire is_ddc_cfg   = (f_cmd == 8'h44) || (f_cmd == 8'h45) ||
                      (f_cmd == 8'h46) || (f_cmd == 8'h47) ||
                      (f_cmd == 8'h48) || (f_cmd == 8'h49);
  wire is_dclk_ps   = (f_cmd == 8'h4a);   // DCLKIO dynamic phase-shift target
  wire is_wave_load = (f_cmd == 8'h50);
  wire is_wave_ctrl = (f_cmd == 8'h51) || (f_cmd == 8'h52);
  wire is_wave_cmd  = is_wave_load || is_wave_ctrl;
  wire is_sys       = (f_cmd == 8'hf0) || (f_cmd == 8'hf1) ||
                      (f_cmd == 8'hf2) || (f_cmd == 8'hfe);
  wire is_known     = is_reg || is_burst || is_chip_ctrl || is_init || is_adc ||
                      is_dac_cmd || is_ddc_cfg || is_dclk_ps || is_wave_cmd || is_sys;

  // Compute bad-id locally — pack_bad sees eff_addr (stale across commands) so isn't usable
  // at decode time for the AD9117 addr[7:5] check.
  wire chip_target     = (f_chip == 8'h01) || (f_chip == 8'h02) || (f_chip == 8'h03);
  wire ad9117_bad_addr = (f_chip == 8'h03) && (f_addr[7:5] != 3'b000);
  // 0x50 uses f_chip[1:0] as chunk_addr[9:8], so f_chip<=0x03 is legal;
  // 0x51/0x52 still require f_chip=0 like other DAC-side configs.
  wire bad_id =
        (f_cmd == 8'hf0 || f_cmd == 8'hf1 || f_cmd == 8'hfe || is_init || is_adc || is_dac_cmd || is_ddc_cfg || is_dclk_ps || is_wave_ctrl)
                                                             ? (f_chip != 8'h00) :
        (is_wave_load)                                       ? (f_chip[7:2] != 6'h00) :
        (f_cmd == 8'hf2)                                     ? (f_chip != 8'hff) :
        (is_reg)                                             ? (!chip_target || ad9117_bad_addr) :
        (is_burst || is_chip_ctrl)                           ? !chip_target :
        1'b1;

  // 0x50 must wait for player to be disabled (avoids URAM read/write contention).
  // Reuses status code 0x06 — new code reserved for "wave player busy".
  wire wave_blocked = is_wave_load && o_wave_play_en;

  // boot_busy locks out SPI-class commands; 0x30 re-arms via ST_ADC_REARM instead of 0x05.
  wire boot_blocked = i_boot_busy &&
                      (is_reg || is_burst || is_chip_ctrl || (f_cmd == 8'h20) || is_dac_cmd);

  wire [7:0] status_now = !is_known             ? 8'h01 :
                           bad_id               ? 8'h02 :
                           boot_blocked         ? 8'h05 :
                           wave_blocked         ? 8'h06 :
                                                 8'h00;
  wire       do_reg_spi = (status_now == 8'h00) && is_reg;
  wire       do_ctrl    = (status_now == 8'h00) && is_chip_ctrl;
  wire       do_burst   = (status_now == 8'h00) && is_burst;

  // ----- chip-control macro encoding ----------------------------------------
  // All three control commands target register 0x00 of the chip:
  //   0x10 soft-reset : write 0x20 then 0x00 (AD9117 sequence; safe no-op for SI5340/AD9640)
  //   0x11 enable     : write 0x00 (enable, clears PD) or 0x20 (disable)
  //   0x12 power-down : write 0x20 (PD)              or 0x00 (resume)
  function [7:0] ctrl_data;
    input [7:0] cmd_in;
    input       step;    // macro_idx[0]
    input [7:0] raw;
    begin
      case (cmd_in)
        8'h10:   ctrl_data = step ? 8'h00 : 8'h20;
        8'h11:   ctrl_data = raw[0] ? 8'h00 : 8'h20;
        8'h12:   ctrl_data = raw[0] ? 8'h20 : 8'h00;
        default: ctrl_data = 8'h00;
      endcase
    end
  endfunction

  function [1:0] macro_count;
    input [7:0] cmd_in;
    begin
      macro_count = (cmd_in == 8'h10) ? 2'd2 : 2'd1;
    end
  endfunction

  // --------------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state        <= ST_IDLE;
      f_cmd        <= 8'h00; f_chip <= 8'h00; f_addr <= 8'h00; f_data <= 8'h00;
      eff_cmd      <= 8'h00; eff_addr <= 8'h00; eff_data <= 8'h00;
      ack_st       <= 8'h00; ack_data <= 8'h00;
      last_chip    <= 8'h00; last_cmd <= 8'h00; last_status <= 8'h00;
      err_reg      <= 8'h00;
      sub_idx      <= 2'd0;
      frame_cnt_l  <= 2'd0;
      macro_idx    <= 2'd0;
      macro_n      <= 2'd1;
      burst_n      <= 8'd0; burst_idx <= 8'd0;
      active       <= 1'b0;
      spi_valid    <= 1'b0;
      o_global_rst <= 1'b0;
      o_boot_start <= 1'b0;
      o_adc_arm    <= 1'b0;
      o_adc_n      <= 14'd0;
      o_adc_rd_addr<= 14'd0;
      o_adc_chan_sel <= 1'b0;
      adc_seen_busy <= 1'b0;
      adc_wait_cnt  <= 32'd0;
      o_dac_tone_en <= 1'b0;
      o_dac_wave_sel <= 3'd0;
      o_dac_hb_bypass <= 1'b0;
      o_dac_freq_word <= 16'd85;  // ~160 kHz at SYS_CLK=122.88 MHz
      o_dac_amp_pct <= 8'd50;
      o_dac_dclk_ps_target <= 16'd0;
      o_nco_freq_word <= 16'd0;
      o_dec_ratio     <= 2'd0;
      o_capture_mode  <= 1'b0;
      o_iq_bypass     <= 1'b1;
      o_fir_bypass    <= 1'b1;
      o_fir_sel       <= 2'd0;
      o_iq_mult_op1   <= 16'sd16384; // 1.0 in Q14
      o_iq_mult_op2   <= 16'sd0;
      o_iq_offset_i   <= 14'sd0;
      o_iq_offset_q   <= 14'sd0;
      o_stream_enable <= 1'b0;
      o_stream_byte_ready <= 1'b0;
      adc_bidx        <= 14'd0;
      adc_bphase      <= 3'd0;
      adc_bxor        <= 8'h00;
      adc_bsample     <= 14'h0000;
      burst_tx_start  <= 1'b0;
      burst_tx_data   <= 8'h00;
      burst_active    <= 1'b0;
      stream_target_bytes <= 16'd0;
      stream_sent_bytes   <= 16'd0;
      stream_xor          <= 8'h00;
      stream_stop_req     <= 1'b0;
      ack_started         <= 1'b0;
      ack_seen_busy       <= 1'b0;
      o_wave_play_en  <= 1'b0;
      o_wave_loop_len_minus1 <= 18'h3FFFF;  // default = full 256K
      o_wave_swap_iq  <= 1'b0;
      o_wave_neg_q    <= 1'b0;
      o_wave_wr_en    <= 1'b0;
      o_wave_wr_addr  <= 18'd0;
      o_wave_wr_data  <= 32'd0;
      wave_byte_idx   <= 10'd0;
      wave_acc0       <= 8'd0;
      wave_acc1       <= 8'd0;
      wave_acc2       <= 8'd0;
      wave_wr_addr_r  <= 18'd0;
    end else begin
      spi_valid      <= 1'b0;
      o_global_rst   <= 1'b0;
      o_boot_start   <= 1'b0;
      burst_tx_start <= 1'b0;
      o_stream_byte_ready <= 1'b0;
      o_wave_wr_en   <= 1'b0;  // default pulse low

      // Surface boot_fsm errors through 0xFE without disturbing UART err codes.
      if ((i_boot_err != 8'h00) && (err_reg == 8'h00))
        err_reg <= i_boot_err;

      case (state)
        ST_IDLE: begin
          active <= 1'b0;
          ack_started   <= 1'b0;
          ack_seen_busy <= 1'b0;
          adc_wait_cnt  <= 32'd0;
          if (rx_valid && (rx_data == 8'haa))
            state <= ST_CMD;
        end

        ST_CMD: begin
          if (rx_valid) begin
            f_cmd <= rx_data;
            state <= ST_CHIP;
          end
        end

        ST_CHIP: begin
          if (rx_valid) begin
            f_chip <= rx_data;
            state  <= ST_ADDR;
          end
        end

        ST_ADDR: begin
          if (rx_valid) begin
            f_addr <= rx_data;
            state  <= ST_DATA;
          end
        end

        ST_DATA: begin
          if (rx_valid) begin
            f_data       <= rx_data;
            last_cmd     <= f_cmd;
            last_chip    <= f_chip;
            last_status  <= status_now;
            ack_st       <= status_now;
            ack_data     <= 8'h00;
            frame_cnt_l  <= pack_frames;
            sub_idx      <= 2'd0;
            macro_idx    <= 2'd0;
            if (status_now != 8'h00) err_reg <= status_now;

            // --- decode ---------------------------------------------------
            if (status_now != 8'h00) begin
              state <= ST_SEND_ACK;
            end else if (f_cmd == 8'hf0) begin
              ack_data <= 8'hbb;
              state    <= ST_SEND_ACK;
            end else if (f_cmd == 8'hf1) begin
              ack_data <= FW_VERSION;
              state    <= ST_SEND_ACK;
            end else if (f_cmd == 8'hfe) begin
              ack_data <= err_reg;
              state    <= ST_SEND_ACK;
            end else if (f_cmd == 8'hf2) begin
              o_global_rst  <= 1'b1;
              o_dac_tone_en <= 1'b0;   // tone must drop with chip-level POR
              o_dac_wave_sel <= 3'd0;
              o_dac_hb_bypass <= 1'b0;
              o_dac_freq_word <= 16'd85;
              o_dac_amp_pct <= 8'd50;
              o_dac_dclk_ps_target <= 16'd0;
              o_nco_freq_word <= 16'd0;
              o_dec_ratio     <= 2'd0;
              o_capture_mode  <= 1'b0;
              o_iq_bypass     <= 1'b1;
              o_fir_bypass    <= 1'b1;
              o_fir_sel       <= 2'd0;
              o_iq_mult_op1   <= 16'sd16384;
              o_iq_mult_op2   <= 16'sd0;
              o_iq_offset_i   <= 14'sd0;
              o_iq_offset_q   <= 14'sd0;
              o_stream_enable <= 1'b0;
              o_adc_chan_sel  <= 1'b0;
              o_wave_play_en  <= 1'b0;
              o_wave_swap_iq  <= 1'b0;
              o_wave_neg_q    <= 1'b0;
              o_wave_loop_len_minus1 <= 18'h3FFFF;
              state         <= ST_SEND_ACK;
            end else if (f_cmd == 8'h40) begin
              // DAC tone enable: data[0] = 1 start, 0 stop
              o_dac_tone_en <= rx_data[0];
              ack_data      <= {7'b0, rx_data[0]};
              state         <= ST_SEND_ACK;
            end else if (f_cmd == 8'h41) begin
              // DAC waveform select + TX halfband bypass:
              //   bit[2:0] wave_sel (0=sine, 1=square, 2=triangle, 3=ramp, 4=dc_test)
              //   bit[7]   hb_bypass (1 = skip 2x halfband, sample-repeat)
              o_dac_wave_sel  <= rx_data[2:0];
              o_dac_hb_bypass <= rx_data[7];
              ack_data        <= {rx_data[7], 4'b0, rx_data[2:0]};
              state           <= ST_SEND_ACK;
            end else if (f_cmd == 8'h42) begin
              // DAC frequency word write (16-bit split):
              //   addr=0 -> freq[15:8], addr=1 -> freq[7:0]
              if (f_addr[0] == 1'b0)
                o_dac_freq_word[15:8] <= rx_data;
              else
                o_dac_freq_word[7:0]  <= rx_data;
              ack_data <= rx_data;
              state    <= ST_SEND_ACK;
            end else if (f_cmd == 8'h43) begin
              // DAC amplitude percent (0..100), values above 100 are clamped.
              o_dac_amp_pct <= (rx_data > 8'd100) ? 8'd100 : rx_data;
              ack_data      <= (rx_data > 8'd100) ? 8'd100 : rx_data;
              state         <= ST_SEND_ACK;
            end else if (f_cmd == 8'h44) begin
              // NCO frequency word write (16-bit split, mirror of 0x42):
              //   addr=0 -> freq[15:8], addr=1 -> freq[7:0]
              // f_out = freq_word * fs / 65536, fs after decimation settings.
              if (f_addr[0] == 1'b0)
                o_nco_freq_word[15:8] <= rx_data;
              else
                o_nco_freq_word[7:0]  <= rx_data;
              ack_data <= rx_data;
              state    <= ST_SEND_ACK;
            end else if (f_cmd == 8'h45) begin
              // RX config:
              //   bit[1:0] dec_ratio, bit2 capture_mode, bit3 fir_bypass,
              //   bit4 iq_bypass, bit[6:5] fir_sel (FIR coeff bank 0..3).
              o_dec_ratio    <= rx_data[1:0];
              o_capture_mode <= rx_data[2];
              o_fir_bypass   <= rx_data[3];
              o_iq_bypass    <= rx_data[4];
              o_fir_sel      <= rx_data[6:5];
              ack_data       <= rx_data;
              state          <= ST_SEND_ACK;
            end else if (f_cmd == 8'h46) begin
              // IQ balance OP1 split write: addr0 hi, addr1 lo
              if (f_addr[0] == 1'b0) o_iq_mult_op1[15:8] <= rx_data;
              else                    o_iq_mult_op1[7:0]  <= rx_data;
              ack_data <= rx_data;
              state    <= ST_SEND_ACK;
            end else if (f_cmd == 8'h47) begin
              // IQ balance OP2 split write: addr0 hi, addr1 lo
              if (f_addr[0] == 1'b0) o_iq_mult_op2[15:8] <= rx_data;
              else                    o_iq_mult_op2[7:0]  <= rx_data;
              ack_data <= rx_data;
              state    <= ST_SEND_ACK;
            end else if (f_cmd == 8'h48) begin
              // IQ I-offset split write: addr0 hi[13:8], addr1 lo[7:0]
              if (f_addr[0] == 1'b0) o_iq_offset_i[13:8] <= rx_data[5:0];
              else                    o_iq_offset_i[7:0]  <= rx_data;
              ack_data <= rx_data;
              state    <= ST_SEND_ACK;
            end else if (f_cmd == 8'h49) begin
              // IQ Q-offset split write: addr0 hi[13:8], addr1 lo[7:0]
              if (f_addr[0] == 1'b0) o_iq_offset_q[13:8] <= rx_data[5:0];
              else                    o_iq_offset_q[7:0]  <= rx_data;
              ack_data <= rx_data;
              state    <= ST_SEND_ACK;
            end else if (f_cmd == 8'h4a) begin
              // DCLKIO dynamic phase-shift target (16-bit split, mirror of 0x42):
              //   addr=0 -> target[15:8], addr=1 -> target[7:0]
              // Absolute PS step position; dac_dclk_ps_ctrl seeks to it.
              if (f_addr[0] == 1'b0)
                o_dac_dclk_ps_target[15:8] <= rx_data;
              else
                o_dac_dclk_ps_target[7:0]  <= rx_data;
              ack_data <= rx_data;
              state    <= ST_SEND_ACK;
            end else if (f_cmd == 8'h50) begin
              // Waveform chunk load (always 1024 bytes = 256 IQ words).
              //   chunk_addr[9:0] = {f_chip[1:0], f_addr[7:0]}
              //   wave_wr_addr_r  = {chunk_addr, 8'h00}  (multiple of 256 samples)
              // f_data (=rx_data) is reserved, ignored. Player must be disabled
              // (wave_blocked → status 0x06).
              wave_wr_addr_r <= {f_chip[1:0], f_addr[7:0], 8'h00};
              wave_byte_idx  <= 10'd0;
              ack_data       <= f_addr;   // echo chunk_addr[7:0] for sanity
              state          <= ST_WAVE_RX;
            end else if (f_cmd == 8'h51) begin
              // Waveform control, sub-address style (mirrors 0x42/0x44):
              //   f_addr=0x00  data[0]      = play_en (atomic enable/disable)
              //   f_addr=0x01  data[7:0]    = loop_len_minus1[7:0]
              //   f_addr=0x02  data[7:0]    = loop_len_minus1[15:8]
              //   f_addr=0x03  data[1:0]    = loop_len_minus1[17:16]
              // Program loop_len fields BEFORE enabling for deterministic length.
              case (f_addr)
                8'h00: o_wave_play_en              <= rx_data[0];
                8'h01: o_wave_loop_len_minus1[7:0]   <= rx_data;
                8'h02: o_wave_loop_len_minus1[15:8]  <= rx_data;
                8'h03: o_wave_loop_len_minus1[17:16] <= rx_data[1:0];
                default: ;
              endcase
              ack_data <= rx_data;
              state    <= ST_SEND_ACK;
            end else if (f_cmd == 8'h52) begin
              // Waveform polarity flags: data[0]=swap_iq, data[1]=neg_q.
              o_wave_swap_iq <= rx_data[0];
              o_wave_neg_q   <= rx_data[1];
              ack_data       <= {6'b0, rx_data[1:0]};
              state          <= ST_SEND_ACK;
            end else if (f_cmd == 8'h20) begin
              // boot trigger — accepted (status_now=00 implies !boot_busy here)
              o_boot_start <= 1'b1;
              ack_data     <= 8'h01;
              state        <= ST_SEND_ACK;
            end else if (f_cmd == 8'h21) begin
              ack_data <= {i_boot_busy, i_boot_done,
                           i_si5340_lolb, i_si5340_losxb,
                           i_boot_chip[3:0]};
              state    <= ST_SEND_ACK;
            end else if (f_cmd == 8'h30) begin
              // ADC arm: N = {f_addr[5:0], f_data[7:0]} (14-bit sample count,
              // 1..16383 direct, 0 → 16384 full buffer).
              o_adc_n       <= {f_addr[5:0], rx_data};
              adc_seen_busy <= 1'b0;
              adc_wait_cnt  <= 32'd0;
              if (i_adc_busy || o_adc_arm) begin
                // Abort stale capture so N can latch on the next arm rising edge.
                o_adc_arm <= 1'b0;
                state     <= ST_ADC_REARM;
              end else begin
                o_adc_arm <= 1'b1;
                state     <= ST_ADC_WAIT;
              end
            end else if ((f_cmd == 8'h31) || (f_cmd == 8'h32)) begin
              // ADC read: 0x31 returns sample[13:6]; 0x32 returns {2'b00, sample[5:0]}.
              // f_addr[6] selects channel (0=I/A, 1=Q/B); f_addr[5:0]+f_data form the
              // 14-bit BRAM address. Wait 2 cycles for registered read output.
              o_adc_rd_addr  <= {f_addr[5:0], rx_data};
              o_adc_chan_sel <= f_addr[6];
              sub_idx        <= 2'd0;
              state          <= ST_ADC_RD;
            end else if (f_cmd == 8'h33) begin
              // ADC burst-read: stream 2*o_adc_n raw bytes (hi/lo per sample) then 4-byte
              // ACK with ack_data = XOR8 over the streamed payload.  f_addr[6] picks the
              // channel for the whole burst.
              o_adc_rd_addr  <= 14'd0;
              o_adc_chan_sel <= f_addr[6];
              adc_bidx       <= 14'd0;
              adc_bphase     <= 3'd0;
              adc_bxor       <= 8'h00;
              burst_active   <= 1'b1;
              state          <= ST_ADC_BURST;
            end else if (f_cmd == 8'h34) begin
              // ADC stream read: data field is sample count (14-bit). Each sample emits
              // 4 bytes: I_hi, I_lo, Q_hi, Q_lo.
              //   N>0  → bounded burst of N*4 bytes, then ACK
              //   N==0 → continuous; host terminates by sending any UART byte
              stream_target_bytes <= ({2'b00, f_addr[5:0], rx_data} << 2);
              stream_sent_bytes   <= 16'd0;
              stream_xor          <= 8'h00;
              stream_stop_req     <= 1'b0;
              o_stream_enable     <= 1'b1;
              burst_active        <= 1'b1;
              state               <= ST_ADC_STREAM;
            end else if (do_burst) begin
              burst_n   <= rx_data;
              burst_idx <= 8'd0;
              if (rx_data == 8'd0) begin
                // N==0 is a no-op: report success with data=0
                state <= ST_SEND_ACK;
              end else begin
                state <= ST_BURST_RX;
              end
            end else if (do_reg_spi) begin
              macro_n   <= 2'd1;
              eff_cmd   <= f_cmd;
              eff_addr  <= f_addr;
              eff_data  <= rx_data;
              active    <= 1'b1;
              spi_valid <= 1'b1;
              state     <= ST_WAIT_SPI;
            end else if (do_ctrl) begin
              macro_n   <= macro_count(f_cmd);
              eff_cmd   <= 8'h01;
              eff_addr  <= 8'h00;
              eff_data  <= ctrl_data(f_cmd, 1'b0, rx_data);
              active    <= 1'b1;
              spi_valid <= 1'b1;
              state     <= ST_WAIT_SPI;
            end
          end
        end

        ST_WAIT_SPI: begin
          if (spi_done) begin
            // capture read byte at the last chip-frame of a read
            if ((eff_cmd == 8'h02) && (sub_idx == (frame_cnt_l - 1'b1)))
              ack_data <= pack_rd;

            if (sub_idx == (frame_cnt_l - 1'b1)) begin
              sub_idx <= 2'd0;
              if (macro_idx == (macro_n - 1'b1)) begin
                active <= 1'b0;
                state  <= ST_SEND_ACK;
              end else begin
                macro_idx <= macro_idx + 1'b1;
                eff_data  <= ctrl_data(f_cmd, ~macro_idx[0], f_data);
                spi_valid <= 1'b1;
              end
            end else begin
              sub_idx   <= sub_idx + 1'b1;
              spi_valid <= 1'b1;
            end
          end
        end

        ST_BURST_RX: begin
          if (rx_valid) begin
            eff_cmd   <= 8'h01;
            eff_addr  <= f_addr + burst_idx;
            eff_data  <= rx_data;
            sub_idx   <= 2'd0;
            macro_idx <= 2'd0;
            macro_n   <= 2'd1;
            active    <= 1'b1;
            spi_valid <= 1'b1;
            state     <= ST_BURST_SPI;
          end
        end

        ST_BURST_SPI: begin
          if (spi_done) begin
            if (sub_idx == (frame_cnt_l - 1'b1)) begin
              sub_idx <= 2'd0;
              if (burst_idx == (burst_n - 1'b1)) begin
                ack_data <= burst_n;
                active   <= 1'b0;
                state    <= ST_SEND_ACK;
              end else begin
                burst_idx <= burst_idx + 1'b1;
                state     <= ST_BURST_RX;
              end
            end else begin
              sub_idx   <= sub_idx + 1'b1;
              spi_valid <= 1'b1;
            end
          end
        end

        ST_ADC_REARM: begin
          o_adc_arm <= 1'b0;
          if (!i_adc_busy) begin
            o_adc_arm     <= 1'b1;
            adc_seen_busy <= 1'b0;
            adc_wait_cnt  <= 32'd0;
            state         <= ST_ADC_WAIT;
          end
        end

        ST_ADC_WAIT: begin
          // Hold o_adc_arm until adc_capture finishes (sticky i_adc_done or busy drop).
          o_adc_arm <= 1'b1;
          // New 0xAA resyncs the command parser without a board reset (Ping recovery).
          if (rx_valid && (rx_data == 8'haa)) begin
            o_adc_arm     <= 1'b0;
            adc_seen_busy <= 1'b0;
            adc_wait_cnt  <= 32'd0;
            state         <= ST_CMD;
          end else begin
            if (adc_wait_cnt < ADC_WAIT_TIMEOUT_CYC)
              adc_wait_cnt <= adc_wait_cnt + 32'd1;
            if (i_adc_busy)
              adc_seen_busy <= 1'b1;
            if (i_adc_done || (adc_seen_busy && !i_adc_busy)) begin
              o_adc_arm     <= 1'b0;
              adc_seen_busy <= 1'b0;
              adc_wait_cnt  <= 32'd0;
              ack_data      <= 8'h00;
              state         <= ST_SEND_ACK;
            end else if (adc_wait_cnt >= ADC_WAIT_TIMEOUT_CYC) begin
              o_adc_arm     <= 1'b0;
              adc_seen_busy <= 1'b0;
              adc_wait_cnt  <= 32'd0;
              ack_st        <= 8'h05;
              ack_data      <= 8'h00;
              last_status   <= 8'h05;
              err_reg       <= 8'h05;
              state         <= ST_SEND_ACK;
            end
          end
        end

        ST_ADC_RD: begin
          // sub_idx=0: addr settled, BRAM sampling this cycle
          // sub_idx=1: BRAM output (rd_data_r) valid — capture and ACK.
          // 14-bit sample split across two reads:
          //   0x31 → ack_data = sample[13:6]            (high 8 bits)
          //   0x32 → ack_data = {2'b00, sample[5:0]}    (low 6 bits in lower bits)
          // Reconstruction: sample14 = (hi << 6) | (lo & 0x3F)
          sub_idx <= sub_idx + 1'b1;
          if (sub_idx == 2'd1) begin
            ack_data <= (f_cmd == 8'h32) ? {2'b00, i_adc_rdata[5:0]}
                                         : i_adc_rdata[13:6];
            sub_idx  <= 2'd0;
            state    <= ST_SEND_ACK;
          end
        end

        ST_ADC_BURST: begin
          // Streaming readout. Per sample: phase 0 sets addr; phase 1 latches BRAM;
          // phase 2 transmits hi byte; phase 3 transmits lo byte; phase 4 advances.
          // o_adc_n was latched by the most recent 0x30 arm; if N==0 (wire form for
          // 16384) we treat that as a full 16384-sample burst.
          case (adc_bphase)
            3'd0: begin
              // o_adc_rd_addr was set on entry (or by phase 4); BRAM sampling this cycle.
              adc_bphase <= 3'd1;
            end
            3'd1: begin
              adc_bsample <= i_adc_rdata;
              adc_bphase  <= 3'd2;
            end
            3'd2: begin
              if (!tx_stream_busy && !burst_tx_start) begin
                burst_tx_data  <= adc_bsample[13:6];
                burst_tx_start <= 1'b1;
                adc_bxor       <= adc_bxor ^ adc_bsample[13:6];
                adc_bphase     <= 3'd3;
              end
            end
            3'd3: begin
              // wait for hi byte to finish, then push lo
              if (!tx_stream_busy && !burst_tx_start) begin
                burst_tx_data  <= {2'b00, adc_bsample[5:0]};
                burst_tx_start <= 1'b1;
                adc_bxor       <= adc_bxor ^ {2'b00, adc_bsample[5:0]};
                adc_bphase     <= 3'd4;
              end
            end
            3'd4: begin
              // wait for lo byte to finish, then advance or terminate. o_adc_n==0 is the
              // wire form for 16384; 0-1 underflows to 14'h3FFF=16383, so the equality
              // works uniformly for 1..16383 and the N=16384 case.
              if (!tx_stream_busy && !burst_tx_start) begin
                if (adc_bidx == (o_adc_n - 14'd1)) begin
                  // payload done — emit ACK trailer via the main 4-byte tx path.
                  burst_active <= 1'b0;
                  ack_data     <= adc_bxor;
                  ack_st       <= 8'h00;
                  state        <= ST_SEND_ACK;
                end else begin
                  adc_bidx      <= adc_bidx + 14'd1;
                  o_adc_rd_addr <= adc_bidx + 14'd1;
                  adc_bphase    <= 3'd0;
                end
              end
            end
            default: adc_bphase <= 3'd0;
          endcase
        end

        ST_ADC_STREAM: begin
          // Latch any UART RX byte as stop request (only acted on in continuous mode).
          o_stream_enable <= 1'b1;
          if (rx_valid) stream_stop_req <= 1'b1;
          if ((stream_done) && !tx_stream_busy && !burst_tx_start) begin
            burst_active        <= 1'b0;
            o_stream_enable     <= 1'b0;
            stream_stop_req     <= 1'b0;
            ack_st              <= i_stream_overflow ? 8'h05 : 8'h00;
            ack_data            <= stream_xor;
            state               <= ST_SEND_ACK;
          end else if (!tx_stream_busy && !burst_tx_start && i_stream_byte_vld) begin
            // !burst_tx_start guard: tx_stream_busy doesn't rise until two
            // cycles after we pulse burst_tx_start (one for the NBA, one for
            // u_tx_byte to register busy<=1). Without this, the cycle right
            // after we fire still sees !tx_stream_busy and we'd double-fire —
            // incrementing stream_sent_bytes twice per actually-transmitted
            // byte. That trips the bounded-stream done condition after only
            // half the bytes were sent, leaving the rest stranded and the
            // monitor uart_rx with nothing to receive. ST_ADC_BURST already
            // uses the same gate; mirror it here.
            burst_tx_data       <= i_stream_byte;
            burst_tx_start      <= 1'b1;
            o_stream_byte_ready <= 1'b1;
            stream_sent_bytes   <= stream_sent_bytes + 16'd1;
            stream_xor          <= stream_xor ^ i_stream_byte;
          end
        end

        ST_WAVE_RX: begin
          // Receive 1024 bytes from UART, pack 4 bytes -> one URAM word, write.
          // Wire order is LE: I_lo, I_hi, Q_lo, Q_hi → URAM word = {I[15:0], Q[15:0]}.
          if (rx_valid) begin
            case (wave_byte_idx[1:0])
              2'd0: wave_acc0 <= rx_data;          // I_lo
              2'd1: wave_acc1 <= rx_data;          // I_hi
              2'd2: wave_acc2 <= rx_data;          // Q_lo
              2'd3: begin
                // All 4 bytes in hand: form URAM word and fire write.
                o_wave_wr_data <= {wave_acc1, wave_acc0,   // I = {I_hi, I_lo}
                                   rx_data,   wave_acc2};  // Q = {Q_hi, Q_lo}
                o_wave_wr_addr <= wave_wr_addr_r;
                o_wave_wr_en   <= 1'b1;
                wave_wr_addr_r <= wave_wr_addr_r + 18'd1;
              end
            endcase
            if (wave_byte_idx == 10'd1023) begin
              wave_byte_idx <= 10'd0;
              ack_data      <= 8'h00;
              state         <= ST_SEND_ACK;
            end else begin
              wave_byte_idx <= wave_byte_idx + 10'd1;
            end
          end
        end

        // Keep ST_SEND_ACK until uart_tx really starts and finishes. This avoids
        // losing ACK and also avoids duplicate ACK retrigger.
        ST_SEND_ACK: begin
          if (!ack_seen_busy) begin
            // Pulse tx_start for one cycle; if busy didn't rise, retry.
            if (!ack_started)
              ack_started <= 1'b1;
            else if (!tx_main_busy)
              ack_started <= 1'b0;

            if (tx_main_busy) begin
              ack_seen_busy <= 1'b1;
              ack_started   <= 1'b0;
            end
          end else if (!tx_main_busy) begin
            ack_seen_busy <= 1'b0;
            ack_started   <= 1'b0;
            state         <= ST_IDLE;
          end
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule
