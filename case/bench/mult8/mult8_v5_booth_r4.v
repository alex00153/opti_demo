// mult8 v5: unsigned radix-4 modified Booth (5 partial products) + correction + tree add
module mult8(input [7:0] a, input [7:0] b, output [15:0] y);
  wire [2:0] enc [0:4];
  wire [8:0] mag [0:4];
  wire neg [0:4];
  wire [16:0] term [0:4];
  wire [16:0] corr;
  genvar i;
  generate
    assign enc[0] = {b[1], b[0], 1'b0};
    assign enc[1] = {b[3], b[2], b[1]};
    assign enc[2] = {b[5], b[4], b[3]};
    assign enc[3] = {b[7], b[6], b[5]};
    assign enc[4] = {1'b0, 1'b0, b[7]};   // unsigned top digit: always +a or 0
    for (i = 0; i < 5; i = i + 1) begin : ppg
      wire [24:0] tmp;
      wire [16:0] shifted;
      assign neg[i] = enc[i][2];
      // magnitude table (depends on enc[2] only for the 00/11 patterns)
      assign mag[i] = (enc[i][1:0] == 2'b01) ? {1'b0, a} :
                      (enc[i][1:0] == 2'b10) ? {1'b0, a} :
                      (enc[i][1:0] == 2'b00) ? (enc[i][2] ? {a, 1'b0} : 9'b0) :
                                                (enc[i][2] ? 9'b0 : {a, 1'b0});
      assign tmp = ({2'b0, mag[i]} << (2*i));
      assign shifted = tmp[16:0];
      assign term[i] = neg[i] ? ~shifted : shifted;
    end
    assign corr = (neg[0]?17'd1:17'd0) + (neg[1]?17'd1:17'd0) + (neg[2]?17'd1:17'd0) +
                  (neg[3]?17'd1:17'd0) + (neg[4]?17'd1:17'd0);
  endgenerate
  assign y = (term[0] + term[1] + term[2] + term[3] + term[4] + corr) & 16'hFFFF;
endmodule
