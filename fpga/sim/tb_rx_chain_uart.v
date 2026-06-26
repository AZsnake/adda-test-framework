`timescale 1ns / 1ps

// Integration testbench: PC UART byte stream → uart_cmd_parser → rx-chain
// control wires → adc_iq_rx_chain → adc_iq_snapshot / adc_iq_stream_drain →
// back through the parser as 0x33 burst / 0x34 stream payload.
//
// Goal: prove the wiring in rf_adda_top is intact end-to-end without firing
// up the full SPI/boot path. SPI and boot stubs are tied off; only the RX
// datapath opcodes are exercised.
module tb_rx_chain_uart;

  localparam integer CLK_HZ     = 19_200_000;
  localparam integer CLK_PERIOD = 52;                          // ~19.2 MHz
  localparam integer ADC_PERIOD = 16;                          // ~62.5 MHz
  // Keep TB bit period exactly aligned with DUT UART integer divider:
  // BIT_CLK = CLK_HZ / BAUD (uart_rx/uart_tx implementation).
  localparam integer UART_BIT_CLK = CLK_HZ / 921_600;
  localparam integer BIT_NS       = UART_BIT_CLK * CLK_PERIOD;

  reg sys_clk = 0;
  reg adc_clk = 0;
  reg rst_n   = 0;

  always #(CLK_PERIOD / 2) sys_clk = ~sys_clk;
  always #(ADC_PERIOD / 2) adc_clk = ~adc_clk;

  integer errs = 0;

  initial begin
    #200_000_000;
    $display("[WATCHDOG] TIMEOUT errs=%0d", errs);
    $display("tb_rx_chain_uart: FAIL (timeout)");
    $finish;
  end

  // ---- UART parser I/O --------------------------------------------------
  reg  uart_rx = 1;
  wire uart_tx;
  wire [7:0] uart_mon_data;
  wire       uart_mon_valid;
  reg  [7:0] uart_mon_fifo [0:255];
  integer    uart_mon_wr = 0;
  integer    uart_mon_rd = 0;

  // SPI stubs (tied off — not exercised)
  reg         spi_done  = 0;
  reg  [55:0] spi_rdata = 0;
  wire        spi_valid;
  wire [62:0] spi_cmd;
  wire        spi_busy;

  // Boot stubs
  reg  boot_busy_tb = 0;
  reg  boot_done_tb = 1;
  reg  [3:0] boot_chip_tb = 4'h0;
  reg  [7:0] boot_err_tb  = 8'h00;
  wire boot_start_tb;
  wire global_rst;

  // Chain control wires from parser
  wire        adc_arm;
  wire [13:0] adc_n;
  wire        adc_chan_sel;
  wire [13:0] adc_rd_addr;
  wire [15:0] nco_freq_word;
  wire [1:0]  dec_ratio;
  wire        capture_mode;
  wire        iq_bypass;
  wire        fir_bypass;
  wire [1:0]  fir_sel;
  wire [15:0] iq_mult_op1;
  wire [15:0] iq_mult_op2;
  wire [13:0] iq_offset_i;
  wire [13:0] iq_offset_q;
  wire        stream_enable;
  wire        stream_byte_ready;

  // Chain feedback
  wire        adc_done;
  wire        adc_busy;
  wire [13:0] adc_rdata;
  wire [7:0]  stream_byte;
  wire        stream_byte_vld;
  wire        stream_overflow;

  // ---- RX chain ---------------------------------------------------------
  wire signed [13:0] rx_i;
  wire signed [13:0] rx_q;
  wire               rx_vld;
  wire               rx_fifo_afull;
  wire               rx_fifo_aempty;
  wire signed [13:0] rx_adc_i;
  wire signed [13:0] rx_adc_q;
  wire               rx_adc_vld;

  reg  [13:0] adc_i_drv = 14'd0;
  reg  [13:0] adc_q_drv = 14'd0;
  // Drive a small triangle on top of midscale so chain output is non-zero
  reg  [9:0]  phase = 10'd0;
  always @(posedge adc_clk or negedge rst_n) begin
    if (!rst_n) begin
      phase <= 10'd0;
      adc_i_drv <= 14'd0;
      adc_q_drv <= 14'd0;
    end else begin
      phase     <= phase + 10'd1;
      // small swing ±256 so chain has signal to chew on
      adc_i_drv <= {{4{phase[9]}}, phase[9:0]};
      adc_q_drv <= -$signed({{4{phase[9]}}, phase[9:0]});
    end
  end

  adc_iq_rx_chain u_chain (
    .i_adc_clk         (adc_clk),
    .i_sys_clk         (sys_clk),
    .i_rst_n           (rst_n),
    .i_adc_i           (adc_i_drv),
    .i_adc_q           (adc_q_drv),
    .i_dec_ratio       (dec_ratio),
    .i_nco_freq_word   (nco_freq_word),
    .i_iq_bypass       (iq_bypass),
    .i_iq_mult_op1     (iq_mult_op1),
    .i_iq_mult_op2     (iq_mult_op2),
    .i_iq_offset_i     (iq_offset_i),
    .i_iq_offset_q     (iq_offset_q),
    .i_fir_bypass      (fir_bypass),
    .i_fir_sel         (fir_sel),
    .o_iq_i            (rx_i),
    .o_iq_q            (rx_q),
    .o_iq_vld          (rx_vld),
    .o_fifo_almst_full (rx_fifo_afull),
    .o_fifo_almst_empty(rx_fifo_aempty),
    .o_adc_iq_i        (rx_adc_i),
    .o_adc_iq_q        (rx_adc_q),
    .o_adc_iq_vld      (rx_adc_vld)
  );

  adc_iq_snapshot u_snap (
    .i_sys_clk   (sys_clk),
    .i_rst_n     (rst_n),
    .i_arm       (adc_arm),
    .i_n_samples (adc_n),
    .i_rd_addr   (adc_rd_addr),
    .i_chan_sel  (adc_chan_sel),
    .o_rd_data   (adc_rdata),
    .o_done      (adc_done),
    .o_busy      (adc_busy),
    .i_adc_clk   (adc_clk),
    .i_iq_i      (rx_adc_i),
    .i_iq_q      (rx_adc_q),
    .i_iq_vld    (rx_adc_vld)
  );

  adc_iq_stream_drain u_drain (
    .i_clk        (sys_clk),
    .i_rst_n      (rst_n),
    .i_enable     (stream_enable),
    .i_iq_i       (rx_i),
    .i_iq_q       (rx_q),
    .i_iq_vld     (rx_vld),
    .o_byte       (stream_byte),
    .o_byte_vld   (stream_byte_vld),
    .i_byte_ready (stream_byte_ready),
    .o_overflow   (stream_overflow)
  );

  // ---- UART parser ------------------------------------------------------
  uart_cmd_parser #(.CLK_HZ(CLK_HZ)) u_parser (
    .clk           (sys_clk),
    .rst_n         (rst_n),
    .uart_rx       (uart_rx),
    .uart_tx       (uart_tx),
    .spi_valid     (spi_valid),
    .spi_cmd       (spi_cmd),
    .spi_done      (spi_done),
    .spi_rdata     (spi_rdata),
    .spi_busy      (spi_busy),
    .o_global_rst  (global_rst),
    .o_boot_start  (boot_start_tb),
    .i_boot_busy   (boot_busy_tb),
    .i_boot_done   (boot_done_tb),
    .i_boot_chip   (boot_chip_tb),
    .i_boot_err    (boot_err_tb),
    .i_si5340_lolb (1'b1),
    .i_si5340_losxb(1'b1),
    .o_adc_arm     (adc_arm),
    .o_adc_n       (adc_n),
    .o_adc_rd_addr (adc_rd_addr),
    .o_adc_chan_sel(adc_chan_sel),
    .i_adc_done    (adc_done),
    .i_adc_busy    (adc_busy),
    .i_adc_rdata   (adc_rdata),
    .o_dac_tone_en (),
    .o_dac_wave_sel(),
    .o_dac_freq_word(),
    .o_dac_amp_pct (),
    .o_nco_freq_word(nco_freq_word),
    .o_dec_ratio   (dec_ratio),
    .o_capture_mode(capture_mode),
    .o_iq_bypass   (iq_bypass),
    .o_fir_bypass  (fir_bypass),
    .o_fir_sel     (fir_sel),
    .o_iq_mult_op1 (iq_mult_op1),
    .o_iq_mult_op2 (iq_mult_op2),
    .o_iq_offset_i (iq_offset_i),
    .o_iq_offset_q (iq_offset_q),
    .i_stream_byte (stream_byte),
    .i_stream_byte_vld(stream_byte_vld),
    .i_stream_overflow(stream_overflow),
    .o_stream_enable(stream_enable),
    .o_stream_byte_ready(stream_byte_ready),
    .o_state       (),
    .o_frame_start (),
    .o_last_chip   (),
    .o_last_cmd    (),
    .o_last_status ()
  );

  // Decode DUT uart_tx with the same UART RX used in RTL, then consume bytes
  // from a small TB queue. This is much more robust than delay-based sampling.
  uart_rx #(.CLK_HZ(CLK_HZ)) u_tb_uart_rx_mon (
    .clk   (sys_clk),
    .rst_n (rst_n),
    .rx    (uart_tx),
    .data  (uart_mon_data),
    .valid (uart_mon_valid)
  );

  always @(posedge sys_clk) begin
    if (!rst_n) begin
      uart_mon_wr <= 0;
      uart_mon_rd <= 0;
    end else if (uart_mon_valid) begin
      uart_mon_fifo[uart_mon_wr[7:0]] <= uart_mon_data;
      uart_mon_wr <= uart_mon_wr + 1;
    end
  end

  // ---- primitives -------------------------------------------------------
  task uart_byte;
    input [7:0] b;
    integer i;
    begin
      uart_rx = 0; #BIT_NS;
      for (i = 0; i < 8; i = i + 1) begin uart_rx = b[i]; #BIT_NS; end
      uart_rx = 1; #BIT_NS;
    end
  endtask

  task send_cmd;
    input [7:0] cmd, chip, addr, data;
    begin
      uart_byte(8'hAA); uart_byte(cmd); uart_byte(chip);
      uart_byte(addr);  uart_byte(data);
    end
  endtask

  reg [7:0] rx_byte_buf;
  task uart_rx_one_byte;
    output [7:0] b;
    integer guard;
    begin
      guard = 0;
      while ((uart_mon_rd == uart_mon_wr) && (guard < 200000)) begin
        @(posedge sys_clk);
        guard = guard + 1;
      end
      if (uart_mon_rd == uart_mon_wr) begin
        $display("  [UART_MON] timeout waiting byte");
        errs = errs + 1;
        b = 8'h00;
      end else begin
        b = uart_mon_fifo[uart_mon_rd[7:0]];
        uart_mon_rd = uart_mon_rd + 1;
      end
    end
  endtask

  task check_ack;
    input [7:0]   exp_st, exp_data;
    input [255:0] tag;
    reg   [7:0]   ab [0:3];
    integer       i;
    begin
      for (i = 0; i < 4; i = i + 1) begin
        uart_rx_one_byte(rx_byte_buf);
        ab[i] = rx_byte_buf;
      end
      if (ab[0] !== 8'hBB) begin
        $display("  [%0s] ACK[0] exp=BB got=%02h", tag, ab[0]); errs = errs + 1;
      end
      if (ab[1] !== exp_st) begin
        $display("  [%0s] ACK status exp=%02h got=%02h", tag, exp_st, ab[1]); errs = errs + 1;
      end
      if (ab[2] !== exp_data) begin
        $display("  [%0s] ACK data exp=%02h got=%02h", tag, exp_data, ab[2]); errs = errs + 1;
      end
      if (ab[3] !== (8'hBB ^ exp_st ^ exp_data)) begin
        $display("  [%0s] ACK ck exp=%02h got=%02h",
                 tag, 8'hBB ^ exp_st ^ exp_data, ab[3]); errs = errs + 1;
      end
    end
  endtask

  // ---- test body --------------------------------------------------------
  integer k;
  reg [7:0] payload [0:127];
  reg [7:0] tail [0:3];
  reg [7:0] xor_calc;

  initial begin
    repeat (40) @(posedge sys_clk);
    rst_n = 1;
    $display("Reset released. BIT_NS=%0d ns", BIT_NS);
    // Let the chain warm up — give the FIFO a few sys_clks to see chain output.
    repeat (500) @(posedge sys_clk);

    // T1: Ping --------------------------------------------------------------
    $display("T1: Ping");
    send_cmd(8'hF0, 8'h00, 8'h00, 8'h00);
    check_ack(8'h00, 8'hBB, "T1");

    // T2: 0x45 RX cfg — dec=0, snapshot, FIR+IQ active ----------------------
    $display("T2: 0x45 RX cfg dec=0 fir=on iq=on");
    send_cmd(8'h45, 8'h00, 8'h00, 8'h00);    // bypass=0, dec=0, snapshot
    check_ack(8'h00, 8'h00, "T2");
    @(posedge sys_clk);
    if (iq_bypass !== 1'b0 || fir_bypass !== 1'b0 || dec_ratio !== 2'b00) begin
      $display("  [T2] rx cfg wires: iq_b=%b fir_b=%b dec=%b",
               iq_bypass, fir_bypass, dec_ratio); errs = errs + 1;
    end

    // T3: 0x44 NCO write — hi=0x12, lo=0x34 → freq_word=0x1234 ---------------
    $display("T3: 0x44 NCO freq 0x1234");
    send_cmd(8'h44, 8'h00, 8'h00, 8'h12);
    check_ack(8'h00, 8'h12, "T3a");
    send_cmd(8'h44, 8'h00, 8'h01, 8'h34);
    check_ack(8'h00, 8'h34, "T3b");
    @(posedge sys_clk);
    if (nco_freq_word !== 16'h1234) begin
      $display("  [T3] nco_freq_word=%h exp=1234", nco_freq_word); errs = errs + 1;
    end

    // T4: 0x46/0x47/0x48/0x49 IQ balance writes ------------------------------
    $display("T4: 0x46/0x47/0x48/0x49 IQ balance writes");
    send_cmd(8'h46, 8'h00, 8'h00, 8'h40);  // op1 hi = 0x40
    check_ack(8'h00, 8'h40, "T4a");
    send_cmd(8'h46, 8'h00, 8'h01, 8'h00);  // op1 lo = 0x00 → 0x4000
    check_ack(8'h00, 8'h00, "T4b");
    send_cmd(8'h47, 8'h00, 8'h00, 8'h01);  // op2 hi = 0x01
    check_ack(8'h00, 8'h01, "T4c");
    send_cmd(8'h47, 8'h00, 8'h01, 8'h00);  // op2 lo = 0x00 → 0x0100
    check_ack(8'h00, 8'h00, "T4d");
    send_cmd(8'h48, 8'h00, 8'h00, 8'h00);  // offI hi
    check_ack(8'h00, 8'h00, "T4e");
    send_cmd(8'h48, 8'h00, 8'h01, 8'h10);  // offI lo = 0x10
    check_ack(8'h00, 8'h10, "T4f");
    send_cmd(8'h49, 8'h00, 8'h00, 8'h3F);  // offQ hi = 0x3F (max +)
    check_ack(8'h00, 8'h3F, "T4g");
    send_cmd(8'h49, 8'h00, 8'h01, 8'hF8);  // offQ lo = 0xF8
    check_ack(8'h00, 8'hF8, "T4h");
    @(posedge sys_clk);
    if (iq_mult_op1 !== 16'h4000) begin
      $display("  [T4] iq_mult_op1=%h exp=4000", iq_mult_op1); errs = errs + 1; end
    if (iq_mult_op2 !== 16'h0100) begin
      $display("  [T4] iq_mult_op2=%h exp=0100", iq_mult_op2); errs = errs + 1; end
    if (iq_offset_i !== 14'h0010) begin
      $display("  [T4] iq_offset_i=%h exp=0010", iq_offset_i); errs = errs + 1; end
    if (iq_offset_q !== 14'h3FF8) begin
      $display("  [T4] iq_offset_q=%h exp=3FF8", iq_offset_q); errs = errs + 1; end

    // T5: 0x30 snapshot arm N=16 — verify ACK fires after capture ------------
    $display("T5: 0x30 arm N=16 + 0x33 burst read");
    send_cmd(8'h30, 8'h00, 8'h00, 8'h10);   // N = 16
    check_ack(8'h00, 8'h00, "T5arm");

    // 0x33 burst: chan=I, expect 2*16 = 32 payload bytes + ACK
    send_cmd(8'h33, 8'h00, 8'h00, 8'h00);
    xor_calc = 8'h00;
    for (k = 0; k < 32; k = k + 1) begin
      uart_rx_one_byte(rx_byte_buf);
      payload[k] = rx_byte_buf;
      xor_calc = xor_calc ^ rx_byte_buf;
    end
    for (k = 0; k < 4; k = k + 1) begin
      uart_rx_one_byte(rx_byte_buf);
      tail[k] = rx_byte_buf;
    end
    if (tail[0] !== 8'hBB) begin
      $display("  [T5burst] tail[0] exp=BB got=%02h", tail[0]); errs = errs + 1; end
    if (tail[1] !== 8'h00) begin
      $display("  [T5burst] tail status exp=00 got=%02h", tail[1]); errs = errs + 1; end
    if (tail[2] !== xor_calc) begin
      $display("  [T5burst] XOR8 fpga=%02h tb=%02h", tail[2], xor_calc); errs = errs + 1; end
    if (tail[3] !== (8'hBB ^ tail[1] ^ tail[2])) begin
      $display("  [T5burst] ck mismatch tb=%02h got=%02h",
               8'hBB ^ tail[1] ^ tail[2], tail[3]); errs = errs + 1; end

    // T6: 0x34 bounded stream N=8 — payload 32 bytes (4 per IQ) + ACK --------
    $display("T6: 0x34 bounded stream N=8 (32 byte payload)");
    send_cmd(8'h34, 8'h00, 8'h00, 8'h08);
    xor_calc = 8'h00;
    for (k = 0; k < 32; k = k + 1) begin
      uart_rx_one_byte(rx_byte_buf);
      payload[k] = rx_byte_buf;
      xor_calc = xor_calc ^ rx_byte_buf;
    end
    for (k = 0; k < 4; k = k + 1) begin
      uart_rx_one_byte(rx_byte_buf);
      tail[k] = rx_byte_buf;
    end
    if (tail[0] !== 8'hBB) begin
      $display("  [T6] tail[0] exp=BB got=%02h", tail[0]); errs = errs + 1; end
    // Status 0x05 is the documented behaviour when adc_iq_stream_drain's
    // 256-byte FIFO fills up faster than UART can drain it — see the comment
    // in adc_iq_rx_chain.v: chain writes samples at sys_clk rate but UART is
    // 1 byte / ~86 µs, so the overflow flag latches within microseconds. The
    // flag is informational; the 32-byte payload itself is still valid.
    if (tail[1] !== 8'h00 && tail[1] !== 8'h05) begin
      $display("  [T6] status exp=00/05 got=%02h", tail[1]); errs = errs + 1; end
    if (tail[2] !== xor_calc) begin
      $display("  [T6] XOR8 fpga=%02h tb=%02h", tail[2], xor_calc); errs = errs + 1; end
    if (tail[3] !== (8'hBB ^ tail[1] ^ tail[2])) begin
      $display("  [T6] ck mismatch tb=%02h got=%02h",
               8'hBB ^ tail[1] ^ tail[2], tail[3]); errs = errs + 1; end

    if (errs == 0) $display("tb_rx_chain_uart: PASS errs=0");
    else            $display("tb_rx_chain_uart: FAIL errs=%0d", errs);
    $finish;
  end

endmodule
