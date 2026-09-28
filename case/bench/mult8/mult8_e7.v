// e7_symmetric: evolved by evolve_mult.py round2  variant=(swap_smaller)  md5=1cc09917
module mult8(input [7:0] a, input [7:0] b, output [15:0] y);

  // 对称优化：小乘数作移位控制（a<b 交换）
  wire [7:0] x = (a < b) ? b : a;
  wire [7:0] yv = (a < b) ? a : b;
  reg [15:0] acc;
  integer i;
  always @(*) begin
    acc = 16'd0;
    for (i = 0; i < 8; i = i + 1)
      if (yv[i]) acc = acc + ({8'b0, x} << i);
  end
  assign y = acc;
endmodule
