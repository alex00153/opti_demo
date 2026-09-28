// mac8_v7_seq_pipe4: sequential 4-parallel MACs, 2 cycles
module TopModule(input clk, input rst,
  input [7:0] x0, c0, input [7:0] x1, c1, input [7:0] x2, c2, input [7:0] x3, c3, input [7:0] x4, c4, input [7:0] x5, c5, input [7:0] x6, c6, input [7:0] x7, c7,
  input start, output reg done, output reg [18:0] y);
  reg [0:0] i;
  reg [18:0] acc;
  always @(posedge clk or posedge rst) begin
    if (rst) begin i <= 0; acc <= 0; done <= 0; end
    else if (start) begin i <= 0; acc <= 0; done <= 0; end
    else if (!done) begin
      case (i)
        1'd0: acc <= acc + x0*c0 + x1*c1 + x2*c2 + x3*c3;
        default: begin acc <= acc + x4*c4 + x5*c5 + x6*c6 + x7*c7; done <= 1; y <= acc + x4*c4 + x5*c5 + x6*c6 + x7*c7; end
      endcase
      i <= i + 1;
    end
  end
endmodule
