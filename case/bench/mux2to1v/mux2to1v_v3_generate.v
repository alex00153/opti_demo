// mux2to1v v3: generate per-bit 2:1
module TopModule(input [99:0] a, input [99:0] b, input sel, output [99:0] out);
  genvar i;
  generate
    for (i = 0; i < 100; i = i + 1) begin : muxg
      assign out[i] = sel ? b[i] : a[i];
    end
  endgenerate
endmodule
