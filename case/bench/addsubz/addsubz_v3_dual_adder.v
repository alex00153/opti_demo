// addsubz v3: dual parallel adders (a+b and a-b) + mux
module TopModule(input do_sub, input [7:0] a, input [7:0] b, output reg [7:0] out, output reg result_is_zero);
  wire [7:0] sum = a + b;
  wire [7:0] dif = a - b;
  always @(*) begin
    out = do_sub ? dif : sum;
    result_is_zero = (out == 8'b0);
  end
endmodule
