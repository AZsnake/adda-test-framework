// boot_rom — synchronous-read ROM initialised from a $readmemh image.
// Holds concatenated SI5340 / AD9640 / AD9117 init tables; entry format:
//   {opcode[3:0], chip[3:0], page[7:0], addr[7:0], data[7:0]}
// See fpga/scripts/cbpro_to_mem.py and docs/uart_command_protocol.md §boot.
module boot_rom #(
  parameter integer DEPTH    = 512,
  parameter         MEM_FILE = "boot_rom.mem"
) (
  input  wire                          clk ,
  input  wire [$clog2(DEPTH)-1:0]      addr,
  output reg  [31:0]                   data
);

  reg [31:0] rom [0:DEPTH-1];

  initial begin : init
    integer i;
    for (i = 0; i < DEPTH; i = i + 1) rom[i] = 32'h0;
    $readmemh(MEM_FILE, rom);
  end

  always @(posedge clk) data <= rom[addr];

endmodule
