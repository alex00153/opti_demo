// e2_halfword4: evolved by evolve_mult.py round2  variant=(halfword_4x4_merge)  md5=4b28d68e
module mult8(input [7:0] a, input [7:0] b, output [15:0] y);

  wire [3:0] al = a[3:0], ah = a[7:4], bl = b[3:0], bh = b[7:4];
  wire [7:0] pp_al_bl[0:3];
  wire [7:0] pr_al_bl;
  genvar g_al_bl;
  generate
    for (g_al_bl = 0; g_al_bl < 4; g_al_bl = g_al_bl + 1) begin : ppg_al_bl
      assign pp_al_bl[g_al_bl] = ({4'b0, ({4{al[g_al_bl]}} & bl)} << g_al_bl);
    end
    assign pr_al_bl = pp_al_bl[0] + pp_al_bl[1] + pp_al_bl[2] + pp_al_bl[3];
  endgenerate  wire [7:0] pp_al_bh[0:3];
  wire [7:0] pr_al_bh;
  genvar g_al_bh;
  generate
    for (g_al_bh = 0; g_al_bh < 4; g_al_bh = g_al_bh + 1) begin : ppg_al_bh
      assign pp_al_bh[g_al_bh] = ({4'b0, ({4{al[g_al_bh]}} & bh)} << g_al_bh);
    end
    assign pr_al_bh = pp_al_bh[0] + pp_al_bh[1] + pp_al_bh[2] + pp_al_bh[3];
  endgenerate  wire [7:0] pp_ah_bl[0:3];
  wire [7:0] pr_ah_bl;
  genvar g_ah_bl;
  generate
    for (g_ah_bl = 0; g_ah_bl < 4; g_ah_bl = g_ah_bl + 1) begin : ppg_ah_bl
      assign pp_ah_bl[g_ah_bl] = ({4'b0, ({4{ah[g_ah_bl]}} & bl)} << g_ah_bl);
    end
    assign pr_ah_bl = pp_ah_bl[0] + pp_ah_bl[1] + pp_ah_bl[2] + pp_ah_bl[3];
  endgenerate  wire [7:0] pp_ah_bh[0:3];
  wire [7:0] pr_ah_bh;
  genvar g_ah_bh;
  generate
    for (g_ah_bh = 0; g_ah_bh < 4; g_ah_bh = g_ah_bh + 1) begin : ppg_ah_bh
      assign pp_ah_bh[g_ah_bh] = ({4'b0, ({4{ah[g_ah_bh]}} & bh)} << g_ah_bh);
    end
    assign pr_ah_bh = pp_ah_bh[0] + pp_ah_bh[1] + pp_ah_bh[2] + pp_ah_bh[3];
  endgenerate
  assign y = pr_al_bl + (pr_al_bh << 4) + (pr_ah_bl << 4) + (pr_ah_bh << 8);
endmodule
