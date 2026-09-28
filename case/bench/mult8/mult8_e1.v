// e1_serial_loop: evolved by evolve_mult.py round2  variant=(serial_for)  md5=5d547b6b
module mult8(input [7:0] a, input [7:0] b, output [15:0] y);

  reg [15:0] acc;
  integer i;
  always @(*) begin
    acc = 16'd0;
    for (i = 0; i < 8; i = i + 1)
      if (b[i]) acc = acc + ({8'b0, a} << i);
  end
  assign y = acc;
endmodule
