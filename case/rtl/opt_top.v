// opti_demo RTL 基线设计（自包含）
//
// 功能：两条 8x8 乘法路径，根据 sel 选择其中一条输出。
//   sel=0 -> y = a * b
//   sel=1 -> y = c * d
//
// 结构上实例化了两个乘法器（p1、p2）再二选一，存在资源复用空间：
// 每个周期只用到一个乘积，可用一个乘法器共享实现，从而减小面积。
module opt_top #(
    parameter W = 8
) (
    input  wire [W-1:0]   a,
    input  wire [W-1:0]   b,
    input  wire [W-1:0]   c,
    input  wire [W-1:0]   d,
    input  wire           sel,
    output wire [2*W-1:0] y
);

    wire [2*W-1:0] p1 = a * b;   // 乘法器 1
    wire [2*W-1:0] p2 = c * d;   // 乘法器 2

    assign y = sel ? p2 : p1;

endmodule
