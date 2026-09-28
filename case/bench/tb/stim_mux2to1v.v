`timescale 1ps/1ps
module tb;
  reg [99:0] a, b; reg sel; wire [99:0] out;
  TopModule dut(.a(a), .b(b), .sel(sel), .out(out));
  integer k; reg [31:0] rnd;
  initial begin
    $dumpfile("__VCD__");
    $dumpvars(1, dut);
    rnd = __SEED__;
    a=0; b=0; sel=0;
    for (k = 0; k < 2000; k = k + 1) begin
      rnd = (rnd * 1103515245 + 12345) & 32'hFFFFFFFF;
      a = {rnd, rnd ^ 32'hCAFEBABE, ~rnd, 4'b0};
      b = {~rnd, rnd, rnd | 32'h0F0F0F0F, 4'b1111};
      sel = rnd[0];
      #10;
    end
    $finish;
  end
endmodule