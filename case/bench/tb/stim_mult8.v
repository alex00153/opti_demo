`timescale 1ps/1ps
module tb;
  reg [7:0] a; reg [7:0] b;
  wire [15:0] y;
  mult8 dut(.a(a), .b(b), .y(y));
  integer k; reg [31:0] rnd;
  initial begin
    $dumpfile("__VCD__");
    $dumpvars(1, dut);
    rnd = __SEED__; a = 8'd0; b = 8'd0;
    for (k = 0; k < 2000; k = k + 1) begin
      rnd = (rnd * 1103515245 + 12345) & 32'hFFFFFFFF;
      a = rnd[7:0]; b = rnd[15:8];
      #10;
    end
    $finish;
  end
endmodule