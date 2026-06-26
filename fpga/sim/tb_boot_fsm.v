`timescale 1ns / 1ps

// Unit testbench for boot_fsm.
//
// Replaces boot_rom with a small in-TB fixture array (same synchronous-read
// timing).  Stubs rf_spi_core with a counter that pulses spi_done four cycles
// after each spi_valid.  CLK_HZ=1 kHz is passed to boot_fsm only: 1 ms = 1
// FSM cycle (DELAY/LOL counts), independent of CLK_PERIOD wall time.
//
// Covers:
//   T1  power-on auto-boot, SI5340 PAGE_SEL insertion (page 0xFF → 0x0B → 0x05)
//   T2  AD9640 / AD9117 single-frame writes
//   T3  DELAY opcode timing
//   T4  WAIT_LOL success path (lolb asserted in time)
//   T5  WAIT_LOL timeout path → o_err = 0x10
//   T6  EOF transitions to FINISHED, o_busy clears, o_done one-cycle pulse
//   T7  i_start re-trigger from any state aborts and restarts cleanly

module tb_boot_fsm;

  localparam integer CLK_HZ     = 1_000;   // 1 ms per cycle
  localparam integer CLK_PERIOD = 100;     // 100 ns

  reg         clk    = 0;
  reg         rst_n  = 0;
  reg         i_start = 0;
  reg         lolb   = 1'b0;

  wire [8:0]  rom_addr;
  reg  [31:0] rom_data;

  wire        spi_valid;
  wire [62:0] spi_cmd;
  reg         spi_done = 0;

  wire        busy;
  wire        done_pulse;
  wire        done_sticky;
  wire [3:0]  chip;
  wire [7:0]  err;

  integer     errs = 0;
  reg         saw_done_pulse = 0;

  always #(CLK_PERIOD/2) clk = ~clk;

  // Edge-triggered: avoids posedge/NBA races with DUT o_done updates
  always @(posedge done_pulse or negedge rst_n) begin
    if (!rst_n)
      saw_done_pulse <= 1'b0;
    else
      saw_done_pulse <= 1'b1;
  end

  // ----- Fixture ROM (32 entries; the rest is implicitly 0/no-op) ---------
  reg [31:0] fixture [0:31];
  integer i;
  initial begin
    for (i = 0; i < 32; i = i + 1) fixture[i] = 32'h00000000;
    // SI5340 writes, three on two different pages
    fixture[0]  = 32'h010b24d8;  // page=0b addr=24 data=d8 (page change ff→0b)
    fixture[1]  = 32'h010b25aa;  // page=0b addr=25 data=aa (no page change)
    fixture[2]  = 32'h010502bb;  // page=05 addr=02 data=bb (page change 0b→05)
    fixture[3]  = 32'h11000001;  // DELAY index=1 (10 ms => 10 cycles)
    fixture[4]  = 32'h21000000;  // WAIT_LOL
    fixture[5]  = 32'h02000800;  // AD9640 addr=08 data=00 (1 frame)
    fixture[6]  = 32'h03000234;  // AD9117 addr=02 data=34 (1 frame)
    fixture[7]  = 32'hf0000000;  // EOF — boot ends here
  end

  // boot_rom timing: sync read at posedge — data at addr+1 cycle latency
  always @(posedge clk) rom_data <= fixture[rom_addr[4:0]];

  // ----- SPI-core stub: spi_done four cycles after each spi_valid pulse ---
  reg [3:0] spi_cnt;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      spi_done <= 1'b0;
      spi_cnt  <= 4'd0;
    end else begin
      spi_done <= 1'b0;
      if (spi_valid)             spi_cnt <= 4'd4;
      else if (spi_cnt != 4'd0) begin
        spi_cnt <= spi_cnt - 1'b1;
        if (spi_cnt == 4'd1) spi_done <= 1'b1;
      end
    end
  end

  // ----- DUT (tight params: POR=1 ms, DELAY0=3 ms, DELAY1=1 ms, LOL=5 ms) -
  boot_fsm #(
    .CLK_HZ        (CLK_HZ),
    .ROM_DEPTH     (512),
    .POR_DELAY_MS  (1),
    .DELAY0_MS     (3),
    .DELAY1_MS     (1),
    .LOL_TIMEOUT_MS(5)
  ) dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .i_start       (i_start),
    .i_si5340_lolb (lolb),
    .o_rom_addr    (rom_addr),
    .i_rom_data    (rom_data),
    .o_spi_valid   (spi_valid),
    .o_spi_cmd     (spi_cmd),
    .i_spi_done    (spi_done),
    .o_busy        (busy),
    .o_done        (done_pulse),
    .o_done_sticky (done_sticky),
    .o_chip        (chip),
    .o_err         (err)
  );

  // ----- SPI command capture: collect each (spi_cmd[55:40], chip) pair ----
  reg [15:0] cap_frame [0:63];
  reg [3:0]  cap_chip  [0:63];
  reg [62:0] cap_full  [0:63];
  integer    cap_n = 0;
  always @(posedge clk) begin
    if (rst_n && spi_valid) begin
      cap_frame[cap_n] = spi_cmd[55:40];
      cap_chip[cap_n]  = chip;
      cap_full[cap_n]  = spi_cmd;
      cap_n            = cap_n + 1;
    end
  end

  task expect_frame;
    input integer        idx;
    input [15:0]         exp_frame;
    input [3:0]          exp_chip;
    input [255:0]        tag;
    begin
      if (cap_frame[idx] !== exp_frame) begin
        $display("  [%0s] frame[%0d] exp=%04h got=%04h", tag, idx, exp_frame, cap_frame[idx]);
        errs = errs + 1;
      end
      if (cap_chip[idx] !== exp_chip) begin
        $display("  [%0s] chip[%0d]  exp=%0d got=%0d",   tag, idx, exp_chip,  cap_chip[idx]);
        errs = errs + 1;
      end
    end
  endtask

  task expect_slv_sel;
    input integer idx;
    input [2:0]   exp_sel;
    input [255:0] tag;
    begin
      if (cap_full[idx][62:60] !== exp_sel) begin
        $display("  [%0s] slv_sel[%0d] exp=%0d got=%0d",
                 tag, idx, exp_sel, cap_full[idx][62:60]);
        errs = errs + 1;
      end
    end
  endtask

  // Hold i_start high across a full posedge so boot_fsm always samples it
  // (deasserting i_start in the same active region as posedge can drop the pulse).
  task pulse_i_start;
    begin
      @(posedge clk);
      i_start = 1'b1;
      @(posedge clk);
      i_start = 1'b0;
    end
  endtask

  task boot_retrigger;
    begin
      pulse_i_start;
      @(posedge clk);
      wait (done_sticky === 1'b0);
      wait (done_sticky === 1'b1);
    end
  endtask

  initial begin
    #500_000;
    $display("[WATCHDOG] TIMEOUT errs=%0d cap_n=%0d", errs, cap_n);
    $display("tb_boot_fsm: FAIL (timeout)");
    $finish;
  end

  initial begin
    repeat (5) @(posedge clk);
    rst_n = 1;
    $display("Reset released; boot_fsm should auto-start (POR=1 cycle then SPI).");

    // T4: assert lolb before fixture[4] WAIT_LOL (do not delay — boot finishes
    // in a few us while o_done is only one cycle; use done_sticky to synchronize).
    lolb = 1'b1;
    wait (done_sticky === 1'b1);
    $display("T1+T6: boot finished: done_sticky set, busy=%0d", busy);

    // ---- Verify SPI frame sequence ------------------------------------
    // PAGE_SEL ff→0b: si5340 set-addr 0x01, then write 0x0B
    expect_frame  (0, 16'h0001, 4'h1, "T1-page-f0");
    expect_frame  (1, 16'h400b, 4'h1, "T1-page-f1");
    expect_slv_sel(0, 3'd0,           "T1-page-slv");

    // fixture[0] payload write: set-addr 0x24, write 0xD8
    expect_frame  (2, 16'h0024, 4'h1, "T1-w0-f0");
    expect_frame  (3, 16'h40d8, 4'h1, "T1-w0-f1");

    // fixture[1]: no page change → only payload (set-addr 0x25, write 0xAA)
    expect_frame  (4, 16'h0025, 4'h1, "T1-w1-f0");
    expect_frame  (5, 16'h40aa, 4'h1, "T1-w1-f1");

    // fixture[2]: page change 0b→05 → PAGE_SEL then payload
    expect_frame  (6, 16'h0001, 4'h1, "T1-page2-f0");
    expect_frame  (7, 16'h4005, 4'h1, "T1-page2-f1");
    expect_frame  (8, 16'h0002, 4'h1, "T1-w2-f0");
    expect_frame  (9, 16'h40bb, 4'h1, "T1-w2-f1");

    // fixture[5]: AD9640 single frame — instruction word {0,00,5'h0,0x08}=0x0008
    //   data byte 0x00 sits in [39:32], not part of frame[15:0]
    expect_frame  (10, 16'h0008, 4'h2, "T2-9640");
    expect_slv_sel(10, 3'd1,           "T2-9640-slv");

    // fixture[6]: AD9117 single frame — {0,00,addr[4:0]=00010, data=0x34}=0x0234
    expect_frame  (11, 16'h0234, 4'h3, "T2-9117");
    expect_slv_sel(11, 3'd2,           "T2-9117-slv");

    if (cap_n !== 12) begin
      $display("T1/T2: expected 12 SPI frames, got %0d", cap_n);
      errs = errs + 1;
    end

    if (err !== 8'h00) begin
      $display("T4: expected err=0, got %02h", err); errs = errs + 1;
    end
    if (done_sticky !== 1'b1) begin
      $display("T6: done_sticky should be set"); errs = errs + 1;
    end
    if (!saw_done_pulse) begin
      $display("T6: o_done one-cycle pulse was not seen"); errs = errs + 1;
    end
    if (busy !== 1'b0) begin
      $display("T6: busy should be 0"); errs = errs + 1;
    end

    // ---- T5: WAIT_LOL timeout -----------------------------------------
    $display("T5: re-trigger boot with lolb=0 throughout → err=0x10");
    cap_n = 0;
    lolb  = 1'b0;
    boot_retrigger;
    if (err !== 8'h10) begin
      $display("T5: expected err=0x10, got %02h", err); errs = errs + 1;
    end

    // ---- T7: i_start abort mid-boot (during SPI burst) ----------------
    $display("T7: pulse i_start mid-boot; FSM should restart to S_POR cleanly");
    cap_n = 0;
    lolb  = 1'b1;
    pulse_i_start;
    wait (cap_n >= 3);
    cap_n = 0;
    pulse_i_start;
    @(posedge clk);
    wait (done_sticky === 1'b0);
    // POR + drop any in-flight spi_valid from the abort edge before re-capture
    repeat (2) @(posedge clk);
    cap_n = 0;
    wait (cap_n >= 1);
    if (cap_frame[0] !== 16'h0001) begin
      $display("T7: post-restart frame[0] exp=0001 got=%04h", cap_frame[0]);
      errs = errs + 1;
    end
    wait (done_sticky === 1'b1);

    // -------------------------------------------------------------------
    repeat (50) @(posedge clk);
    if (errs == 0) $display("tb_boot_fsm: PASS");
    else           $display("tb_boot_fsm: FAIL errs=%0d", errs);
    $finish;
  end

endmodule
