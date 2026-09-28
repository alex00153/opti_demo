// e5_karatsuba: evolved by evolve_mult.py round2  variant=(karatsuba_3mul)  md5=8276cd92
module mult8(input [7:0] a, input [7:0] b, output [15:0] y);

  wire [3:0] al = a[3:0], ah = a[7:4], bl = b[3:0], bh = b[7:4];
  wire [7:0] z0 = al * bl;
  wire [7:0] z1 = al * bh;
  wire [7:0] z2 = ah * bl;
  wire [7:0] z3 = ah * bh;
  assign y = z0 + ((z1 + z2) << 4) + (z3 << 8);
endmodule
