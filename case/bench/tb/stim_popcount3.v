`timescale 1ps/1ps
module tb;
  reg [2:0] in; wire [1:0] out;
  TopModule dut(.in(in), .out(out));
  integer k; reg [31:0] rnd;
  initial begin
    $dumpfile("__VCD__");
    $dumpvars(1, dut);
    rnd = __SEED__;
    in = 3'd0;
    for (k = 0; k < 2000; k = k + 1) begin
      rnd = (rnd * 1103515245 + 12345) & 32'hFFFFFFFF;
      in = rnd[2:0];
      #10;
    end
    $finish;
  end
endmodule