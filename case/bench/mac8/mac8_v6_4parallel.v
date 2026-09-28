// mac8 v6: sequential 4-parallel (4 mults, 2 cycles)
module TopModule(input clk, input rst, input start,
                 input [7:0] x0,x1,x2,x3,x4,x5,x6,x7,
                 input [7:0] c0,c1,c2,c3,c4,c5,c6,c7,
                 output reg done, output reg [17:0] y);
  reg i;
  reg [17:0] acc;
  always @(posedge clk or posedge rst) begin
    if (rst) begin i <= 0; acc <= 0; done <= 0; end
    else if (start) begin i <= 0; acc <= 0; done <= 0; end
    else if (!done) begin
      if (!i) acc <= acc + x0*c0+x1*c1+x2*c2+x3*c3;
      else begin acc <= acc + x4*c4+x5*c5+x6*c6+x7*c7; done <= 1; y <= acc + x4*c4+x5*c5+x6*c6+x7*c7; end
      i <= i + 1;
    end
  end
endmodule
