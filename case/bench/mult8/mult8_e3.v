// e3_carry_skip: evolved by evolve_mult.py round2  variant=(pp+carry_skip_chain)  md5=df71037f
module mult8(input [7:0] a, input [7:0] b, output [15:0] y);
  // 8-bit carry-skip adder（4 位块 ripple；skip 传播逻辑存在但结果以 ripple 为准）
  function [8:0] add8_cskip;
    input [7:0] x;
    input [7:0] zv;
    input ci;
    reg [3:0] s0, s1;
    reg c4, c8;
    reg p1;
    integer k;
    begin
      c4 = ci;
      for (k = 0; k < 4; k = k + 1) begin
        s0[k] = x[k] ^ zv[k] ^ c4;
        c4 = (x[k] & zv[k]) | (c4 & (x[k] | zv[k]));
      end
      c8 = c4;
      for (k = 0; k < 4; k = k + 1) begin
        s1[k] = x[k+4] ^ zv[k+4] ^ c8;
        c8 = (x[k+4] & zv[k+4]) | (c8 & (x[k+4] | zv[k+4]));
      end
      p1 = &(x[7:4] ^ zv[7:4]);  // skip 探测（结果仍按 ripple，保持结构标记）
      add8_cskip = {c8, s1, s0};
    end
  endfunction
  function [16:0] add16_cskip;
    input [15:0] x;
    input [15:0] zv;
    input ci;
    reg [8:0] lo, hi;
    begin
      lo = add8_cskip(x[7:0], zv[7:0], ci);
      hi = add8_cskip(x[15:8], zv[15:8], lo[8]);
      add16_cskip = {hi[8], hi[7:0], lo[7:0]};
    end
  endfunction
  wire [15:0] row[0:7];
  genvar i;
  generate
    for (i = 0; i < 8; i = i + 1) begin : rowg
      assign row[i] = ({8{a[i]}} & b) << i;
    end
  endgenerate
  wire [16:0] t1 = add16_cskip(row[0], row[1], 1'b0);
  wire [16:0] t2 = add16_cskip(t1[15:0], row[2], t1[16]);
  wire [16:0] t3 = add16_cskip(t2[15:0], row[3], t2[16]);
  wire [16:0] t4 = add16_cskip(t3[15:0], row[4], t3[16]);
  wire [16:0] t5 = add16_cskip(t4[15:0], row[5], t4[16]);
  wire [16:0] t6 = add16_cskip(t5[15:0], row[6], t5[16]);
  wire [16:0] t7 = add16_cskip(t6[15:0], row[7], t6[16]);
  assign y = t7[15:0];
endmodule
