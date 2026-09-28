module tb;
  reg [2:0] in; wire [1:0] out;
  TopModule dut(.in(in), .out(out));
  integer i, err;
  initial begin
    err = 0;
    for (i = 0; i < 8; i = i + 1) begin
      in = i[2:0]; #1;
      if (out !== (i[0]+i[1]+i[2])) begin if (err < 5) $display("MISMATCH in=%0d out=%0d", in, out); err = err + 1; end
    end
    if (err == 0) $display("PASS 8"); else $display("FAIL %0d", err);
    $finish;
  end
endmodule
