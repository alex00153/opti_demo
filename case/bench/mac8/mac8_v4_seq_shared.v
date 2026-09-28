// mac8 v4: sequential resource-shared (1 mult reused, 8 cycles)
module TopModule(input clk, input rst,
                 input [7:0] x0, x1, x2, x3, x4, x5, x6, x7,
                 input [7:0] c0, c1, c2, c3, c4, c5, c6, c7,
                 input start, output reg done, output reg [17:0] y);
  reg [2:0] i;
  reg [17:0] acc;
  always @(posedge clk or posedge rst) begin
    if (rst) begin i <= 0; acc <= 0; done <= 0; end
    else if (start) begin i <= 0; acc <= 0; done <= 0; end
    else if (!done) begin
      case (i)
        3'd0: acc <= acc + x0*c0;
        3'd1: acc <= acc + x1*c1;
        3'd2: acc <= acc + x2*c2;
        3'd3: acc <= acc + x3*c3;
        3'd4: acc <= acc + x4*c4;
        3'd5: acc <= acc + x5*c5;
        3'd6: acc <= acc + x6*c6;
        default: acc <= acc + x7*c7;
      endcase
      if (i == 3'd7) begin done <= 1; y <= acc + x7*c7; end
      i <= i + 1;
    end
  end
endmodule
