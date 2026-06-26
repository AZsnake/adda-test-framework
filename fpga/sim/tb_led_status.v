`timescale 1ns / 1ps

module tb_led_status;

  localparam integer SIM_FAST      = 1;
  // Keep total runtime under 50 ms in fast mode for one-shot XSim runs.
  localparam integer FAST_SCALE    = SIM_FAST ? 128 : 1;

  localparam integer CLK_HZ        = 19_200_000;
  localparam integer CLK_PERIOD    = 52;
  localparam integer HB_DIV        = CLK_HZ / (2 * FAST_SCALE);
  localparam integer PING_DIV      = CLK_HZ / (10 * FAST_SCALE);
  localparam integer RESULT_TICKS  = CLK_HZ / FAST_SCALE;
  localparam integer OK_PHASE      = CLK_HZ / (8 * FAST_SCALE);
  localparam integer ST_SEND_ACK   = 6;

  reg clk = 0;
  reg rst_n = 0;
  reg [2:0] state = 0;
  reg spi_busy = 0;
  reg frame_start = 0;
  reg [7:0] last_chip = 0;
  reg [7:0] last_cmd = 0;
  reg [7:0] last_status = 0;

  wire led_red, led_blue;
  wire [7:0] strip;

  integer errs = 0;
  integer ok_highs;
  integer i;
  reg [7:0] strip_mid;

  led_status #(
    .HB_DIV(HB_DIV),
    .PING_DIV(PING_DIV),
    .RESULT_TICKS(RESULT_TICKS),
    .OK_PHASE(OK_PHASE)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .state(state),
    .spi_busy(spi_busy),
    .frame_start(frame_start),
    .last_chip(last_chip),
    .last_cmd(last_cmd),
    .last_status(last_status),
    .led_red(led_red),
    .led_blue(led_blue),
    .strip(strip)
  );

  always #(CLK_PERIOD / 2) clk = ~clk;

  task pulse_ack(input [7:0] chip, input [7:0] status);
    begin
      last_chip   = chip;
      last_status = status;
      @(posedge clk);
      state = ST_SEND_ACK;
      @(posedge clk);
      state = 0;
    end
  endtask

  initial begin
    #(SIM_FAST ? 80_000_000 : 500_000_000);
    $display("[WATCHDOG] tb_led_status timeout");
    $display("tb_led_status: FAIL (timeout)");
    $finish;
  end

  initial begin
    $display("tb_led_status: start (SIM_FAST=%0d)", SIM_FAST);
    #(CLK_PERIOD * 20);
    rst_n = 1;
    $display("tb_led_status: reset released");

    // ping-pong: pos must leave 0 within reasonable steps
    repeat (PING_DIV * 24) @(posedge clk);
    if (dut.pos == 3'd0)
      begin
        $display("  FAIL: ping-pong pos stuck at 0");
        errs = errs + 1;
      end

    // ACK success: blue on, strip has 4 all-on phases
    pulse_ack(8'h01, 8'h00);
    if (!led_blue)
      begin
        $display("  FAIL: blue not on after OK ack");
        errs = errs + 1;
      end

    ok_highs = 0;
    for (i = 0; i < 8; i = i + 1) begin
      repeat (OK_PHASE) @(posedge clk);
      if (strip == 8'hff)
        ok_highs = ok_highs + 1;
    end
    if (ok_highs < 4)
      begin
        $display("  FAIL: OK strip flashes=%0d (exp>=4)", ok_highs);
        errs = errs + 1;
      end
    if (led_red)
      begin
        $display("  FAIL: red on during OK");
        errs = errs + 1;
      end

    repeat (RESULT_TICKS) @(posedge clk);

    // ACK fail: red on, strip pattern changes (LFSR)
    pulse_ack(8'h02, 8'h02);
    if (!led_red)
      begin
        $display("  FAIL: red not on after ERR ack");
        errs = errs + 1;
      end

    repeat (RESULT_TICKS / 4) @(posedge clk);
    strip_mid = strip;
    repeat (PING_DIV * 4) @(posedge clk);
    if (strip == strip_mid)
      begin
        $display("  FAIL: ERR strip static (lfsr not advancing)");
        errs = errs + 1;
      end

    repeat (RESULT_TICKS) @(posedge clk);
    if (led_red)
      begin
        $display("  FAIL: red still on after ERR period");
        errs = errs + 1;
      end

    if (errs == 0)
      $display("tb_led_status: PASS");
    else
      $display("tb_led_status: FAIL errs=%0d", errs);
    $finish;
  end

endmodule
