// popcount3 v3: half-adder tree (2 HAs)
module TopModule(input [2:0] in, output [1:0] out);
  wire s1 = in[0] ^ in[1];
  wire c1 = in[0] & in[1];
  wire s2 = s1 ^ in[2];
  wire c2 = c1 | (s1 & in[2]);
  assign out = {c2, s2};
endmodule
