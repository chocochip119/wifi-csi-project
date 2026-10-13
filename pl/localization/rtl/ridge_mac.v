`timescale 1ns/1ps
// Pipelined 16x16 signed multiplier + 64-bit accumulator.
// Product registered in MUL; added in MAC. Bias is seeded on START/new class.
module ridge_mac(
    input wire aclk, aresetn,
    input wire start_ok, f_mul, f_mac, class_next,
    input wire [31:0] w_read_q, x_read_q,
    input wire [13:0] weight_idx, input wire [9:0] feature_idx,
    input wire signed [63:0] bias0, bias_next,
    output reg signed [63:0] accumulator,
    output wire signed [63:0] sum_next
);
    // Packed half selection is determined by the *current* feature/weight
    // indices in the original RTL. These are supplied explicitly below.
    // See revised interface in top (weight_idx, feature_idx).
    reg signed [31:0] product_q;
    wire signed [15:0] wt = weight_idx[0] ? $signed(w_read_q[31:16]) : $signed(w_read_q[15:0]);
    wire signed [15:0] xt = feature_idx[0] ? $signed(x_read_q[31:16]) : $signed(x_read_q[15:0]);
    wire signed [31:0] product = wt * xt;
    wire signed [63:0] product_ext = {{32{product_q[31]}},product_q};
    assign sum_next = accumulator + product_ext;
    always @(posedge aclk) begin
        if (!aresetn) begin
            accumulator<=0; product_q<=0;
        end else begin
            if (start_ok) accumulator<=bias0;
            if (f_mul) product_q<=product;
            if (f_mac) accumulator<=sum_next;
            if (class_next) accumulator<=bias_next;
        end
    end
endmodule
