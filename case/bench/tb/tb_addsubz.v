module tb;
  reg do_sub; reg [7:0] a, b; wire [7:0] out; wire result_is_zero;
  TopModule dut(.do_sub(do_sub), .a(a), .b(b), .out(out), .result_is_zero(result_is_zero));
  integer i, j, s, err;
  initial begin
    err = 0;
    for (s = 0; s < 2; s = s + 1)
      for (i = 0; i < 256; i = i + 1)
        for (j = 0; j < 256; j = j + 1) begin
          do_sub = s; a = i[7:0]; b = j[7:0];
          #1;
          if (out !== ((s ? i - j : i + j) & 8'hFF)) begin
            if (err < 10) $display("MISMATCH do_sub=%0d a=%0d b=%0d out=%0d", s, i, j, out);
            err = err + 1;
          end
          if (result_is_zero !== (out == 8'b0)) begin
            if (err < 10) $display("ZERO MISMATCH do_sub=%0d a=%0d b=%0d", s, i, j);
            err = err + 1;
          end
        end
    if (err == 0) $display("PASS 131072"); else $display("FAIL %0d", err);
    $finish;
  end
endmodule