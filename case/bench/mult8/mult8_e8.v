// e8_booth_r2: evolved by evolve_mult.py round2  variant=(booth_radix2)  md5=04e38c41
module mult8(input [7:0] a, input [7:0] b, output [15:0] y);

  // Booth radix-2：sel = b[i-1]-b[i]（b[-1]=0, b[8]=0）：(1,0) 结束 1 串→减；(0,1) 开始 1 串→加
  // acc 用 signed 17 位防中间值下溢（Booth 中间可为负）
  reg signed [16:0] acc;
  reg [8:0] be;
  integer i;
  always @(*) begin
    be = {1'b0, b};
    acc = 17'sd0;
    for (i = 0; i < 9; i = i + 1) begin
      case ({be[i], (i == 0) ? 1'b0 : be[i-1]})
        2'b01: acc = acc + {{9'b0, a} << i};
        2'b10: acc = acc - {{9'b0, a} << i};
        default: ;
      endcase
    end
  end
  assign y = acc[15:0];
endmodule
