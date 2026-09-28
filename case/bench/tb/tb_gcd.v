module tb;
  reg clk, rst, start; reg [7:0] a, b; wire done; wire [7:0] g;
  TopModule dut(.clk(clk),.rst(rst),.start(start),.a(a),.b(b),.done(done),.g(g));
  integer k, err; reg [31:0] rnd; reg [7:0] x, y, exp;
  initial begin
    err = 0; rnd = 5150; clk = 0; rst = 1; start = 0; a = 0; b = 0;
    #5 rst = 0;
    for (k = 0; k < 50; k = k + 1) begin
      rnd = (rnd * 1103515245 + 12345) & 32'hFFFFFFFF; a = rnd[7:0];
      rnd = (rnd * 1103515245 + 12345) & 32'hFFFFFFFF; b = rnd[7:0];
      x = a; y = b;
      while (y != 0) begin x = x % y; x = x ^ y; y = x ^ y; x = x ^ y; end
      exp = x;
      start = 1; #5; clk = 1; #5; clk = 0; start = 0; #2;
      if (g !== exp) begin
        if (err < 5) $display("MISMATCH k=%0d a=%0d b=%0d g=%0d exp=%0d", k, a, b, g, exp);
        err = err + 1;
      end
    end
    if (err == 0) $display("PASS %0d cases", 50); else $display("FAIL err=%0d", err);
    $finish;
  end
endmodule
