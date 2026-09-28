`timescale 1ps/1ps
module tb;
  reg clk, rst, start; reg [7:0] a, b;
  wire done; wire [7:0] g;
  TopModule dut(.clk(clk), .rst(rst), .start(start), .a(a), .b(b), .done(done), .g(g));
  integer k, cyc; reg [31:0] rnd;
  initial begin
    $dumpfile("__VCD__");
    $dumpvars(1, dut);
    rnd = __SEED__; clk=0; rst=1; start=0; a=0; b=0;
    #10; rst=0; start=1; #10;
    for (k = 0; k < 2000; k = k + 1) begin
      rnd = (rnd * 1103515245 + 12345) & 32'hFFFFFFFF;
      a = rnd[7:0];
      rnd = (rnd * 1103515245 + 12345) & 32'hFFFFFFFF;
      b = rnd[7:0];
      start = 1; #5; clk = 1; #5; clk = 0; start = 0;
      for (cyc = 0; cyc < 600 && !done; cyc = cyc + 1) begin #5; clk = 1; #5; clk = 0; end
    end
    $finish;
  end
endmodule
