module tb;
  reg [7:0] a, b;
  wire [15:0] y;
  mult8 dut(.a(a), .b(b), .y(y));
  integer i, j, err;
  initial begin
    err = 0;
    for (i = 0; i < 256; i = i + 1)
      for (j = 0; j < 256; j = j + 1) begin
        a = i[7:0]; b = j[7:0];
        #1;
        if (y !== i*j) begin
          if (err < 10) $display("MISMATCH a=%0d b=%0d y=%0d exp=%0d", a, b, y, i*j);
          err = err + 1;
        end
      end
    if (err == 0) $display("PASS all 65536"); else $display("FAIL %0d", err);
    $finish;
  end
endmodule
