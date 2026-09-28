// gcd_v1_euclid_mod: LLM 式变异（evolve_gcd.py, C 扩量第二批新任务族）variant=(euclid_mod_iter) md5=403b5965
module TopModule(input clk, input rst, input start, input [7:0] a, input [7:0] b,
  output reg done, output reg [7:0] g);

  integer i;
  reg [7:0] x, y, r;
  always @(*) begin
    x = a; y = b;
    for (i = 0; i < 16; i = i + 1) begin
      if (y != 0) begin r = x % y; x = y; y = r; end
    end
    g = x;
    done = 1'b1;
  end
endmodule
