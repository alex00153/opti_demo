// gcd_v5_binary_simple: LLM 式变异（evolve_gcd.py, C 扩量第二批新任务族）variant=(binary_gcd_shift_sub) md5=69a45699
module TopModule(input clk, input rst, input start, input [7:0] a, input [7:0] b,
  output reg done, output reg [7:0] g);

  // 二进制 GCD：纯移位+减法（公共 2 因子记录 + 单偶移除 + 减法）
  integer i;
  reg [7:0] x, y;
  reg [2:0] k;
  always @(*) begin
    x = a; y = b; k = 0;
    for (i = 0; i < 24; i = i + 1) begin
      if (x != 0 && y != 0) begin
        if (x[0] == 0 && y[0] == 0) begin x = x >> 1; y = y >> 1; k = k + 1; end
        else if (x[0] == 0) x = x >> 1;
        else if (y[0] == 0) y = y >> 1;
        else if (x >= y) x = x - y;
        else y = y - x;
      end
    end
    g = (x | y) << k;
    done = 1'b1;
  end
endmodule
