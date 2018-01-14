// copied from altera's examples:
// https://www.altera.com/support/support-resources/design-examples/design-software/verilog/ver-single-port-ram.html

module single_port_ram
#(parameter
  ADDR_WIDTH = 11,
  DATA_WIDTH = 32
)
(
  input [DATA_WIDTH - 1: 0] data,
  input [ADDR_WIDTH - 1: 0] addr,
  input we, clk,
  output [DATA_WIDTH - 1: 0] q
);

// Declare the RAM variable
reg [DATA_WIDTH - 1: 0] ram[2 ** ADDR_WIDTH - 1: 0];

// Variable to hold the registered read address
reg [DATA_WIDTH - 1: 0] addr_reg;

always @ (posedge clk)
begin
  // Write
  if (we)
  begin
    ram[addr] <= data;
  end
  addr_reg <= addr;
end

// Continuous assignment implies read returns NEW data.
// This is the natural behavior of the TriMatrix memory
// blocks in Single Port mode.  
assign q = ram[addr_reg];

endmodule
