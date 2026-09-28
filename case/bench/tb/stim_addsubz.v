`timescale 1ps/1ps
module tb;
  reg do_sub; reg [7:0] a; reg [7:0] b;
  wire [7:0] out; wire result_is_zero;
  TopModule dut(.do_sub(do_sub), .a(a), .b(b), .out(out), .result_is_zero(result_is_zero));
  integer k; reg [31:0] rnd;
  initial begin
    $dumpfile("__VCD__");
    $dumpvars(1, dut);
    rnd = __SEED__; do_sub=0; a=0; b=0;
    for (k = 0; k < 2000; k = k + 1) begin
      rnd = (rnd * 1103515245 + 12345) & 32'hFFFFFFFF;
      a = rnd[7:0]; b = rnd[15:8]; do_sub = rnd[16];
      #10;
    end
    $finish;
  end
endmodule