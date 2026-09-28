// e6_csa_array: evolved by evolve_mult.py round2  variant=(csa_array_rowwise)  md5=ac9bbe5e
module mult8(input [7:0] a, input [7:0] b, output [15:0] y);

  // 经典阵列乘法器：每行部分积 + 行内 (sum, carry) 行波，最终 ripple 合并
  wire [7:0] pp[0:7];
  genvar i;
  generate
    for (i = 0; i < 8; i = i + 1) begin : ppg
      assign pp[i] = {8{a[i]}} & b;
    end
  endgenerate
  wire [15:0] s[0:7];
  wire [15:0] c[0:7];
  assign s[0] = {8'b0, pp[0]};
  assign c[0] = 16'd0;
  generate
    for (i = 1; i < 8; i = i + 1) begin : csag
      // CSA 行：s[i] = s[i-1] ^ (pp[i]<<i) ^ (c[i-1]<<1); c[i] = majority
      wire [15:0] p = {8'b0, pp[i]} << i;
      wire [15:0] cinv = c[i-1] << 1;
      assign s[i] = s[i-1] ^ p ^ cinv;
      assign c[i] = (s[i-1] & p) | (s[i-1] & cinv) | (p & cinv);
    end
  endgenerate
  assign y = s[7] + (c[7] << 1);
endmodule
