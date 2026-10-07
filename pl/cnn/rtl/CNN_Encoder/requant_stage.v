`timescale 1ns / 1ps

module requant_stage #(
    parameter TAG_W = 19  // {rx, layer, oc[4:0], h[6:0], w[3:0]}, rx width = TAG_W - 17
) (
    input wire clk,
    input wire rst_n,
    input wire [31:0] acc,
    input wire acc_valid,
    input wire [TAG_W - 1:0] acc_tag,  // {rx, layer, oc[4:0], h[6:0], w[3:0]}
    output wire [8:0] enc_param_raddr,
    input wire [95:0] enc_param_rdata,  // {shift[31:0], mult[31:0],bias[31:0]}
    output reg [7:0] rq,
    output reg rq_valid,
    output reg [TAG_W - 1:0] rq_tag
);

    reg signed [63:0] acc_r1, acc_r2;
    reg signed [64:0] acc_r3;
    reg signed [65:0] acc_r4;
    reg valid_r1, valid_r2, valid_r3, valid_r4;
    reg [TAG_W - 1:0] tag_r1, tag_r2, tag_r3, tag_r4;

    // stage 0 
    wire tag0_layer = acc_tag[16];
    wire [4:0] tag0_oc = acc_tag[15:11];

    assign enc_param_raddr = tag0_layer ? (9'd16 + tag0_oc) : {4'd0, tag0_oc};

    // stage 1, acc + bias
    reg [95:0] param2;
    wire signed [31:0] sh1 = enc_param_rdata[95:64];
    wire signed [31:0] mult1 = enc_param_rdata[63:32];
    wire signed [31:0] bias1 = enc_param_rdata[31:0];

    wire signed [63:0] acc_bias = acc_r1 + bias1;

    // stage 2, acc * mult
    reg [95:0] param3;
    wire signed [31:0] mult2 = param2[63:32];

    wire signed [64:0] acc_mult = $signed(acc_r2[32:0]) * mult2;

    // stage 3, round shift
    wire signed [31:0] sh3 = param3[95:64];

    // Nearest, halfway away from zero. Keep the full signed shift count:
    // masking it to six bits would turn shift=64 into shift=0.
    wire signed [65:0] value = {acc_r3[64], acc_r3};
    wire signed [65:0] half = 66'sd1 <<< (sh3 - 1);
    reg signed [65:0] acc_sh;
    always @* begin
        if (sh3 > 65) acc_sh = 0;
        else if (sh3 > 0)
            acc_sh = (value + half - ((value < 0) ? 66'sd1 : 66'sd0)) >>> sh3;
        else if (sh3 == 0) acc_sh = value;
        else if (sh3 <= -7)
            acc_sh = (value > 0) ? 66'sd127 : (value < 0) ? -66'sd127 : 66'sd0;
        else if (value > (66'sd127 >>> (-sh3))) acc_sh = 66'sd127;
        else if (value < -(66'sd127 >>> (-sh3))) acc_sh = -66'sd127;
        else acc_sh = value <<< (-sh3);
    end

    // stage 4, saturate
    wire signed [7:0] acc_sat = (acc_r4 < -127) ? -8'sd127 : (acc_r4 > 127) ? 8'sd127 : acc_r4[7:0]; 

    always @(posedge clk) begin
        if (!rst_n) begin
            valid_r1 <= 0;
            valid_r2 <= 0;
            valid_r3 <= 0;
            valid_r4 <= 0;
            rq_valid <= 0;
        end else begin
            // stage 0
            acc_r1   <= $signed(acc);
            valid_r1 <= acc_valid;
            tag_r1   <= acc_tag;
            // stage 1 
            acc_r2 <= acc_bias;
            valid_r2 <= valid_r1;
            tag_r2 <= tag_r1;
            param2 <= enc_param_rdata;
            // stage 2
            acc_r3 <= acc_mult;
            valid_r3 <= valid_r2;
            tag_r3 <= tag_r2;
            param3 <= param2;
            // stage 3
            acc_r4 <= acc_sh;
            valid_r4 <= valid_r3;
            tag_r4 <= tag_r3;
            // stage 4
            rq <= acc_sat;
            rq_valid <= valid_r4;
            rq_tag <= tag_r4;
        end
    end

endmodule
