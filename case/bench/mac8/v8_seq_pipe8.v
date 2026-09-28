// mac8_v8_seq_pipe8: sequential full-parallel (1 cycle, registered)
module TopModule(input clk, input rst,
  input [7:0] x0, c0, input [7:0] x1, c1, input [7:0] x2, c2, input [7:0] x3, c3, input [7:0] x4, c4, input [7:0] x5, c5, input [7:0] x6, c6, input [7:0] x7, c7,
  input start, output reg done, output reg [18:0] y);
  reg [18:0] acc;
  always @(posedge clk or posedge rst) begin
    if (rst) begin acc <= 0; done <= 0; end
    else if (start) begin acc <= 0; done <= 0; end
    else if (!done) begin
      acc <= acc + x0*c0 + x1*c1 + x2*c2 + x3*c3 + x4*c4 + x5*c5 + x6*c6 + x7*c7;
      done <= 1; y <= acc + x0*c0 + x1*c1 + x2*c2 + x3*c3 + x4*c4 + x5*c5 + x6*c6 + x7*c7;
    end
  end
endmodule
