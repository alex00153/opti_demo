// e4_carry_select: evolved by evolve_mult.py round2  variant=(pp+carry_select_chain)  md5=1d3c920a
module mult8(input [7:0] a, input [7:0] b, output [15:0] y);
  // 8-bit carry-select adder（低位块 ripple 定 carry-in；高位块双路径 ripple + mux）
  function [8:0] add8_csel;
    input [7:0] x;
    input [7:0] zv;
    input ci;
    reg [3:0] s0, s1a, s1b;
    reg c4, c8a, c8b;
    integer k;
    begin
      c4 = ci;
      for (k = 0; k < 4; k = k + 1) begin
        s0[k] = x[k] ^ zv[k] ^ c4;
        c4 = (x[k] & zv[k]) | (c4 & (x[k] | zv[k]));
      end
      c8a = 1'b0;
      for (k = 0; k < 4; k = k + 1) begin
        s1a[k] = x[k+4] ^ zv[k+4] ^ c8a;
        c8a = (x[k+4] & zv[k+4]) | (c8a & (x[k+4] | zv[k+4]));
      end
      c8b = 1'b1;
      for (k = 0; k < 4; k = k + 1) begin
        s1b[k] = x[k+4] ^ zv[k+4] ^ c8b;
        c8b = (x[k+4] & zv[k+4]) | (c8b & (x[k+4] | zv[k+4]));
      end
      add8_csel = {c4 ? c8b : c8a, c4 ? s1b : s1a, s0};
    end
  endfunction
  function [16:0] add16_csel;
    input [15:0] x;
    input [15:0] zv;
    input ci;
    reg [8:0] lo, hi;
    begin
      lo = add8_csel(x[7:0], zv[7:0], ci);
      hi = add8_csel(x[15:8], zv[15:8], lo[8]);
      add16_csel = {hi[8], hi[7:0], lo[7:0]};
    end
  endfunction
  wire [15:0] row[0:7];
  genvar i;
  generate
    for (i = 0; i < 8; i = i + 1) begin : rowg
      assign row[i] = ({8{a[i]}} & b) << i;
    end
  endgenerate
  wire [16:0] t1 = add16_csel(row[0], row[1], 1'b0);
  wire [16:0] t2 = add16_csel(t1[15:0], row[2], t1[16]);
  wire [16:0] t3 = add16_csel(t2[15:0], row[3], t2[16]);
  wire [16:0] t4 = add16_csel(t3[15:0], row[4], t3[16]);
  wire [16:0] t5 = add16_csel(t4[15:0], row[5], t4[16]);
  wire [16:0] t6 = add16_csel(t5[15:0], row[6], t5[16]);
  wire [16:0] t7 = add16_csel(t6[15:0], row[7], t6[16]);
  assign y = t7[15:0];
endmodule
