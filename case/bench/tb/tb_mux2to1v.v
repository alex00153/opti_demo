module tb;
  reg [99:0] a, b; reg sel; wire [99:0] out;
  TopModule dut(.a(a), .b(b), .sel(sel), .out(out));
  integer k, err; reg [31:0] rnd;
  initial begin
    err = 0; rnd = 999;
    for (k = 0; k < 2000; k = k + 1) begin
      rnd = (rnd * 1103515245 + 12345) & 32'hFFFFFFFF;
      a = {rnd, rnd ^ 32'hCAFEBABE, ~rnd, 4'b0}; // 100 bits: 32+32+32+4
      b = {~rnd, rnd, rnd | 32'h0F0F0F0F, 4'b1111};
      sel = rnd[0];
      #1;
      if (out !== (sel ? b : a)) begin if (err < 5) $display("MISMATCH k=%0d sel=%0d", k, sel); err = err + 1; end
    end
    if (err == 0) $display("PASS 2000"); else $display("FAIL %0d", err);
    $finish;
  end
endmodule
