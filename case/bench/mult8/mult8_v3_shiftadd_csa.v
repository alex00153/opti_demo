// mult8 v3: unrolled shift-and-add with carry-save accumulation + final CPA
module mult8(input [7:0] a, input [7:0] b, output [15:0] y);
  wire [15:0] row [0:7];
  wire [18:0] s [0:7];
  wire [18:0] c [0:7];
  genvar i;
  generate
    for (i = 0; i < 8; i = i + 1) begin : rowg
      assign row[i] = ({8{a[i]}} & b) << i;
    end
  endgenerate
  assign s[0] = {3'b0, row[0]};
  assign c[0] = 19'b0;
  generate
    for (i = 1; i < 8; i = i + 1) begin : csag
      wire [18:0] cin;
      wire [18:0] r;
      assign cin = c[i-1] << 1;
      assign r = {3'b0, row[i]};
      assign s[i] = s[i-1] ^ cin ^ r;
      assign c[i] = (s[i-1] & cin) | (s[i-1] & r) | (cin & r);
    end
  endgenerate
  assign y = (s[7] + (c[7] << 1)) & 16'hFFFF;
endmodule
