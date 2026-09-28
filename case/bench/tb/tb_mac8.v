module tb;
  reg clk, rst, start;
  reg [7:0] x0,x1,x2,x3,x4,x5,x6,x7;
  reg [7:0] c0,c1,c2,c3,c4,c5,c6,c7;
  wire done; wire [17:0] y;
  TopModule dut(.clk(clk), .rst(rst), .start(start),
    .x0(x0),.x1(x1),.x2(x2),.x3(x3),.x4(x4),.x5(x5),.x6(x6),.x7(x7),
    .c0(c0),.c1(c1),.c2(c2),.c3(c3),.c4(c4),.c5(c5),.c6(c6),.c7(c7),
    .done(done), .y(y));
  integer k, err, cyc; reg [31:0] rnd; reg [17:0] expect;
  initial begin
    err = 0; rnd = 888; clk = 0; rst = 1; start = 0;
    #5 rst = 0;
    for (k = 0; k < 100; k = k + 1) begin
      rnd = (rnd * 1103515245 + 12345) & 32'hFFFFFFFF;
      x0=rnd[7:0]; x1=rnd[15:8]; x2=rnd[23:16]; x3=rnd[31:24];
      rnd = (rnd * 1103515245 + 12345) & 32'hFFFFFFFF;
      x4=rnd[7:0]; x5=rnd[15:8]; x6=rnd[23:16]; x7=rnd[31:24];
      c0=8'd1; c1=8'd2; c2=8'd3; c3=8'd4; c4=8'd5; c5=8'd6; c6=8'd7; c7=8'd8;
      expect = x0*c0+x1*c1+x2*c2+x3*c3+x4*c4+x5*c5+x6*c6+x7*c7;
      start = 1; #5; clk = 1; #5; clk = 0; start = 0;
      for (cyc = 0; cyc < 16 && !done; cyc = cyc + 1) begin
        #5; clk = 1; #5; clk = 0;
      end
      #1;
      if (y !== expect) begin if (err < 5) $display("MISMATCH k=%0d y=%0d exp=%0d done=%0d", k, y, expect, done); err = err + 1; end
    end
    if (err == 0) $display("PASS 100"); else $display("FAIL %0d", err);
    $finish;
  end
endmodule