// gcd_v4_longdiv_mod: LLM 式变异（evolve_gcd.py, C 扩量第二批新任务族）variant=(longdiv_mod_shift) md5=47b5c73f
module TopModule(input clk, input rst, input start, input [7:0] a, input [7:0] b,
  output reg done, output reg [7:0] g);

  integer i, j;
  reg [7:0] x, y, r;
  reg [15:0] t;
  always @(*) begin
    x = a; y = b;
    for (i = 0; i < 16; i = i + 1) begin
      if (y != 0) begin
        // 长除模：r = x % y（移位比较，区别于 v1 的直接 %）
        r = x;
        for (j = 7; j >= 0; j = j - 1) begin
          t = y << j;
          if (r >= t) r = r - t;
        end
        x = y; y = r;
      end
    end
    g = x;
    done = 1'b1;
  end
endmodule
