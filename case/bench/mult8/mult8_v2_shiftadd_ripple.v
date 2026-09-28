// mult8 v2: unrolled shift-and-add with ripple-carry accumulation (8 stages)
module mult8(input [7:0] a, input [7:0] b, output [15:0] y);
  wire [15:0] row [0:7];
  wire [15:0] acc [0:7];
  genvar i;
  generate
    for (i = 0; i < 8; i = i + 1) begin : rowg
      assign row[i] = ({8{a[i]}} & b) << i;
    end
    assign acc[0] = row[0];
    for (i = 1; i < 8; i = i + 1) begin : accg
      assign acc[i] = acc[i-1] + row[i];
    end
  endgenerate
  assign y = acc[7];
endmodule
