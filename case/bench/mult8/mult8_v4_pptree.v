// mult8 v4: partial-product balanced adder tree (3 levels of adders)
module mult8(input [7:0] a, input [7:0] b, output [15:0] y);
  wire [15:0] row [0:7];
  wire [15:0] l1 [0:3];
  wire [15:0] l2 [0:1];
  genvar i;
  generate
    for (i = 0; i < 8; i = i + 1) begin : rowg
      assign row[i] = ({8{a[i]}} & b) << i;
    end
    assign l1[0] = row[0] + row[1];
    assign l1[1] = row[2] + row[3];
    assign l1[2] = row[4] + row[5];
    assign l1[3] = row[6] + row[7];
    assign l2[0] = l1[0] + l1[1];
    assign l2[1] = l1[2] + l1[3];
  endgenerate
  assign y = l2[0] + l2[1];
endmodule
