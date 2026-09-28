// addsubz v2: ripple carry add/sub via xor-select
module TopModule(input do_sub, input [7:0] a, input [7:0] b, output reg [7:0] out, output reg result_is_zero);
  wire [7:0] bb = b ^ {8{do_sub}};
  wire [8:0] sum = a + bb + do_sub;
  always @(*) begin
    out = sum[7:0];
    result_is_zero = (out == 8'b0);
  end
endmodule
