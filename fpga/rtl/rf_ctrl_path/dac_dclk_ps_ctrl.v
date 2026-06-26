`timescale 1ns / 1ps

// DCLKIO dynamic-phase-shift seek controller for clk_wiz_0 (MMCM fine PS).
//
// Drives the Clocking Wizard dynamic phase-shift interface (psclk/psen/psincdec
// /psdone) of the DEDICATED DCLKIO MMCM (clk_wiz_1) to move the current PS
// position toward an absolute target supplied over UART (command 0x4A).  One PS
// step = 1/56 of that MMCM's VCO period.  clk_wiz_1 is fed by sys_clk (122.88
// MHz, VCO ~ 983 MHz) so one step ~ 18 ps and a full 122.88 MHz period (~8.14
// ns) is ~448 steps (90 deg ~ 112 steps).  Verify empirically: the SFDR-vs-
// phase pattern repeats once per period.
//
//   i_target : absolute PS position (steps from the IP's configured 90 deg).
//              0 = nominal mid-eye.  Clamped to PS_MAX.
//   o_cur_pos: live position, for readback / ILA.
//
// clk_wiz_1 is its own MMCM driving ONLY DCLKIO, so its fine-PS moves DCLKIO
// alone (the DB/fabric clock from clk_wiz_0 stays fixed).  See
// docs/dac_ddr_timing_bringup.md.
module dac_dclk_ps_ctrl #(
  parameter integer PS_MAX = 448   // clamp target to ~one VCO/output period
) (
  input  wire        i_clk,        // psclk — drive from sys_clk
  input  wire        i_rst_n,
  input  wire [15:0] i_target,     // desired absolute PS position

  output reg         o_psen,       // -> clk_wiz_0 .psen   (1 psclk pulse)
  output reg         o_psincdec,   // -> clk_wiz_0 .psincdec (1=inc, 0=dec)
  input  wire        i_psdone,     // <- clk_wiz_0 .psdone

  output reg  [15:0] o_cur_pos     // current PS position (readback/debug)
);

  localparam [15:0] PS_MAX16 = PS_MAX;   // truncates the integer param to 16 bits

  // 2-FF sync the (quasi-static) UART target into psclk and clamp it.
  reg [15:0] tgt_meta, tgt_sync;
  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      tgt_meta <= 16'd0; tgt_sync <= 16'd0;
    end else begin
      tgt_meta <= i_target;
      tgt_sync <= (tgt_meta > PS_MAX16) ? PS_MAX16 : tgt_meta;
    end
  end

  localparam S_IDLE = 1'b0, S_WAIT = 1'b1;
  reg state;

  always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      state      <= S_IDLE;
      o_psen     <= 1'b0;
      o_psincdec <= 1'b0;
      o_cur_pos  <= 16'd0;
    end else begin
      o_psen <= 1'b0;                       // default: single-cycle pulse
      case (state)
        S_IDLE: begin
          if (tgt_sync != o_cur_pos) begin
            o_psincdec <= (tgt_sync > o_cur_pos);  // 1 = increment phase
            o_psen     <= 1'b1;                     // one psclk pulse
            state      <= S_WAIT;
          end
        end
        S_WAIT: begin
          // psen held low here; wait for the IP to finish this step.
          if (i_psdone) begin
            o_cur_pos <= o_psincdec ? (o_cur_pos + 16'd1)
                                    : (o_cur_pos - 16'd1);
            state     <= S_IDLE;
          end
        end
      endcase
    end
  end

endmodule
