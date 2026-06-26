// ADDA bring-up: blue/red traffic LEDs + 8-strip effects tied to UART ACK and boot_fsm.
//
// Modes (priority: BOOT > OK/ERR > IDLE):
//   IDLE : blue blinks ~1 Hz, strip single-dot ping-pong 0→7→0
//   BOOT : blue blinks ~5 Hz, strip progress bar by boot_chip
//            chip=1 (SI5340) → 0000_0011  (2 LEDs)
//            chip=2 (AD9640) → 0000_1111  (4 LEDs)
//            chip=3 (AD9117) → 0011_1111  (6 LEDs)
//   OK   : blue solid 1 s, strip all-8 blinks 4× (125 ms half-period)
//   ERR  : blue OFF, red on 1 s, strip LFSR random churn
//
// boot_fsm falling-edge (busy→!busy) post-trigger:
//   err==0 → OK window, err!=0 → ERR window (lfsr seeded with err)
//
module led_status #(
  parameter integer HB_DIV       = 25_000_000,   // blue half-period (cycles)
  parameter integer PING_DIV     = 1_666_667,    // ping-pong step (cycles) — ~33 ms/step at 50 MHz
  parameter integer RESULT_TICKS = 50_000_000,   // 1 s window (cycles); width from $clog2(RESULT_TICKS)
  parameter integer OK_PHASE     = 6_250_000     // strip flash half-period (cycles)
) (
  input         clk,
  input         rst_n,
  input  [2:0]  state,
  input         spi_busy,
  input         frame_start,
  input  [7:0]  last_chip,
  input  [7:0]  last_cmd,
  input  [7:0]  last_status,
  // boot_fsm observability
  input         boot_busy,
  input  [3:0]  boot_chip,
  input  [7:0]  boot_err,
  output        led_red,
  output        led_blue,
  output [7:0]  strip
);

  localparam [1:0] S_IDLE = 2'd0, S_OK = 2'd1, S_ERR = 2'd2, S_BOOT = 2'd3;
  localparam [2:0] ST_SEND_ACK = 3'd6;

  reg [1:0]  mode;
  reg        boot_busy_d;

  // Counters must hold HB_DIV / RESULT_TICKS at 122.88 MHz (≈6.1e7 / 1.23e8).
  // Fixed 32-bit width avoids $clog2 tool quirks and 50 MHz-era [25:0] overflow.
  reg [31:0] hb_t;
  reg        hb;

  // Ping-pong — free-running, shown only in IDLE
  reg [31:0] ping_t;
  reg [2:0]  pos;
  reg        dir;

  // 1-second OK/ERR result window
  reg [31:0] result_t;

  // OK strip: 8 alternating phases of OK_PHASE each
  reg [31:0] ok_ph_t;
  reg [2:0]  ok_ph;

  // ERR strip: 16-bit Galois LFSR, taps 16/14/13/11 (maximal length)
  reg [15:0] lfsr;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mode        <= S_BOOT;   // power-on: boot_fsm always runs first
      boot_busy_d <= 1'b0;
      hb_t        <= 0; hb  <= 0;
      ping_t      <= 0; pos <= 0; dir <= 0;
      result_t    <= 0;
      ok_ph_t     <= 0; ok_ph <= 0;
      lfsr        <= 16'hACE1;
    end else begin
      boot_busy_d <= boot_busy;

      // --- Heartbeat (always) ---
      if (hb_t >= HB_DIV - 1) begin hb_t <= 0; hb <= ~hb; end
      else                          hb_t <= hb_t + 1'b1;

      // --- Ping-pong (always; display gated in assign) ---
      if (ping_t >= PING_DIV - 1) begin
        ping_t <= 0;
        if (!dir) begin if (pos == 3'd7) dir <= 1'b1; else pos <= pos + 1'b1; end
        else      begin if (pos == 3'd0) dir <= 1'b0; else pos <= pos - 1'b1; end
      end else
        ping_t <= ping_t + 1'b1;

      // --- Mode FSM ---
      // Boot has highest priority: any time boot_fsm is busy, override.
      // Falling edge of boot_busy resolves into S_OK / S_ERR for 1 s.
      if (boot_busy) begin
        mode <= S_BOOT;
      end else if (boot_busy_d && !boot_busy) begin
        result_t <= 0; ok_ph_t <= 0; ok_ph <= 0;
        if (boot_err == 8'h00) mode <= S_OK;
        else begin
          lfsr <= {boot_err, boot_err} ^ 16'hA53C;
          mode <= S_ERR;
        end
      end else case (mode)
        S_BOOT: mode <= S_IDLE;  // safety: leave BOOT once boot_busy clears

        S_IDLE: begin
          if (state == ST_SEND_ACK) begin
            result_t <= 0; ok_ph_t <= 0; ok_ph <= 0;
            if (last_status == 8'h00)
              mode <= S_OK;
            else begin
              lfsr <= {last_chip, last_status} ^ 16'h5A5A;
              mode <= S_ERR;
            end
          end
        end

        S_OK: begin
          if (ok_ph_t >= OK_PHASE - 1) begin ok_ph_t <= 0; ok_ph <= ok_ph + 1'b1; end
          else                              ok_ph_t <= ok_ph_t + 1'b1;
          if (result_t >= RESULT_TICKS - 1) mode <= S_IDLE;
          else                              result_t <= result_t + 1'b1;
        end

        S_ERR: begin
          // LFSR advances every PING_DIV cycles (reuse ping_t wrap pulse)
          if (ping_t >= PING_DIV - 1)
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
          if (result_t >= RESULT_TICKS - 1) mode <= S_IDLE;
          else                              result_t <= result_t + 1'b1;
        end

        default: mode <= S_IDLE;
      endcase
    end
  end

  // BOOT-mode heartbeat: blink at ~5× the IDLE rate (use ping_t LSB-ish).
  wire boot_hb = ping_t[$clog2(PING_DIV) - 1];

  // Progress strip: 2/4/6 LEDs lit by chip ID (1/2/3).
  wire [7:0] boot_strip =
       (boot_chip == 4'h1) ? 8'b0000_0011 :
       (boot_chip == 4'h2) ? 8'b0000_1111 :
       (boot_chip == 4'h3) ? 8'b0011_1111 :
                             8'b0000_0001;  // pre-first-chip / sentinel

  assign led_blue = (mode == S_BOOT) ? boot_hb :
                    (mode == S_OK)   ? 1'b1    :
                    (mode == S_ERR)  ? 1'b0    : hb;
  assign led_red  = (mode == S_ERR);
  assign strip    = (mode == S_BOOT) ? boot_strip   :
                    (mode == S_OK)   ? {8{ok_ph[0]}} :
                    (mode == S_ERR)  ? lfsr[7:0]    :
                                       8'h1 << pos;

endmodule
