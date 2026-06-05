// Single-port 512x32 SRAM for rf_ctrl_path (SPI/GPO command table).
// Default: infer Block RAM on Xilinx. Define ASIC only for foundry macro flows.

module spram_512x32_w (
  input         CLK,
  input  [ 2:0] T_RWM,
  input         CEB,
  input         WEB,
  input  [31:0] BWEB,
  input  [ 8:0] A,
  input  [31:0] D,
  output [31:0] Q
);

`ifdef ASIC

  // Replace with foundry spram_512x32_w macro in ASIC builds.
  assign Q = 32'b0;

`else

  (* ram_style = "block" *) reg [31:0] mem [0:511];
  reg [31:0] q_r;

  assign Q = q_r;

  // CEB/WEB active-low; rf_spram_mux pipelines Q one cycle (spram_rdata_d1).
  // T_RWM must be 3'b000 (read/write mode); BWEB active-low, all 0 = full-word write.
  always @(posedge CLK) begin
    if (!CEB) begin
      if (!WEB && (T_RWM == 3'b000) && (~|BWEB))
        mem[A] <= D;
      q_r <= mem[A];
    end
  end

`endif

endmodule
