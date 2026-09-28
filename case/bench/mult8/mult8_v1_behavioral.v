// mult8 v1: behavioral (synthesis decides architecture)
module mult8(input [7:0] a, input [7:0] b, output [15:0] y);
  assign y = a * b;
endmodule
