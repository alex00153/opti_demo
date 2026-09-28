// opt_top 预置激励 testbench（等价性验证用）
//
// 只驱动顶层端口、dump 输出波形；同一份 tb 会分别与基线/优化后 RTL 一起仿真，
// 由 equiv_agent.py 逐时刻比对输出端口波形。占位符 __VCD__ / __SEED__ 由脚本替换。
`timescale 1ps/1ps
module tb;
  reg [7:0] a, b, c, d;
  reg       sel;
  wire [15:0] y;

  opt_top dut(.a(a), .b(b), .c(c), .d(d), .sel(sel), .y(y));

  integer k;
  reg [31:0] rnd;

  initial begin
    $dumpfile("__VCD__");
    rnd = __SEED__;
    a = 0; b = 0; c = 0; d = 0; sel = 0;
    #10;
    $dumpvars(1, dut);          // 输入稳定后再开始记录波形

    // 定向：两条乘法路径都覆盖，且 sel 两种取值都走到
    a = 8'hAB; b = 8'h05; c = 8'h07; d = 8'h09; sel = 0; #10;
    a = 8'hAB; b = 8'h05; c = 8'h07; d = 8'h09; sel = 1; #10;
    a = 8'hFF; b = 8'hFF; c = 8'h00; d = 8'hFF; sel = 0; #10;
    a = 8'hFF; b = 8'hFF; c = 8'h00; d = 8'hFF; sel = 1; #10;

    // 随机激励（固定种子，可复现）
    for (k = 0; k < 600; k = k + 1) begin
      rnd = (rnd * 1103515245 + 12345) & 32'hFFFFFFFF; a = rnd[7:0];
      rnd = (rnd * 1103515245 + 12345) & 32'hFFFFFFFF; b = rnd[7:0];
      rnd = (rnd * 1103515245 + 12345) & 32'hFFFFFFFF; c = rnd[7:0];
      rnd = (rnd * 1103515245 + 12345) & 32'hFFFFFFFF; d = rnd[7:0];
      rnd = (rnd * 1103515245 + 12345) & 32'hFFFFFFFF; sel = rnd[0];
      #10;
    end
    $finish;
  end
endmodule
