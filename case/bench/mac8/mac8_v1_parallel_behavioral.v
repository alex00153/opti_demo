// mac8 combinational variant (unified interface: clk/start unused, done=1)
module TopModule(input clk, input rst, input start,
                 input [7:0] x0, x1, x2, x3, x4, x5, x6, x7,
                 input [7:0] c0, c1, c2, c3, c4, c5, c6, c7,
                 output reg done, output reg [17:0] y);
    wire [15:0] m0 = x0*c0, m1 = x1*c1, m2 = x2*c2, m3 = x3*c3;
  wire [15:0] m4 = x4*c4, m5 = x5*c5, m6 = x6*c6, m7 = x7*c7;
  wire [16:0] s01 = {1'b0,m0}+{1'b0,m1}, s23 = {1'b0,m2}+{1'b0,m3};
  wire [16:0] s45 = {1'b0,m4}+{1'b0,m5}, s67 = {1'b0,m6}+{1'b0,m7};
  wire [17:0] s0123 = {1'b0,s01}+{1'b0,s23}, s4567 = {1'b0,s45}+{1'b0,s67};
  always @(*) y = s0123 + s4567;
  always @(*) done = 1'b1;
endmodule
