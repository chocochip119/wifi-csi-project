`timescale 1ns / 1ps

module requant_stage #(
    parameter TAG_WIDTH = 19,
    parameter FC_MODE = 0,
    parameter [8:0] PARAM_BASE0 = 9'd0,
    parameter [8:0] PARAM_BASE1 = 9'd16,
    parameter [8:0] PARAM_BASE2 = 9'd0
) (
    input wire clk,
    input wire rst_n,
    input wire [31:0] acc,
    input wire acc_valid,
    input wire [TAG_WIDTH-1:0] acc_tag,  // Encoder: {rx,layer,oc,h,w}; FC: {sel[1:0],out[6:0]}
    output wire [8:0] enc_param_raddr,
    input wire [95:0] enc_param_rdata,  // {shift[31:0], mult[31:0],bias[31:0]}
    output reg [7:0] rq,
    output reg rq_valid,
    output reg [TAG_WIDTH-1:0] rq_tag
);

    reg signed [63:0] acc_r1, acc_r2, acc_r3;
    reg valid_r1, valid_r2, valid_r3;
    reg [TAG_WIDTH-1:0] tag_r1, tag_r2, tag_r3;

    // stage 0 
    // Zero-extend the 9-bit FC tag before decoding Encoder fields. This
    // avoids out-of-range selects even in the unused constant-mode branch.
    wire [18:0] tag0_decode = acc_tag;
    wire tag0_layer = tag0_decode[16];
    wire [4:0] tag0_oc = tag0_decode[15:11];
    wire [1:0] tag0_fc_sel = tag0_decode[8:7];
    wire [6:0] tag0_fc_idx = tag0_decode[6:0];

    assign enc_param_raddr = FC_MODE ?
        ((tag0_fc_sel == 2'd2) ? (PARAM_BASE2 + tag0_fc_idx) :
         (tag0_fc_sel == 2'd1) ? (PARAM_BASE1 + tag0_fc_idx) :
                                (PARAM_BASE0 + tag0_fc_idx)) :
        (tag0_layer ? (PARAM_BASE1 + tag0_oc) : (PARAM_BASE0 + tag0_oc));

    // stage 1, acc + bias
    reg [95:0] param2;
    wire signed [31:0] sh1 = enc_param_rdata[95:64];
    wire signed [31:0] mult1 = enc_param_rdata[63:32];
    wire signed [31:0] bias1 = enc_param_rdata[31:0];

    wire signed [63:0] acc_bias = acc_r1 + bias1;

    // stage 2, acc * mult
    reg [95:0] param3;
    wire signed [31:0] mult2 = param2[63:32];

    wire signed [63:0] acc_mult = acc_r2 * mult2;

    // stage 3, >> shift and saturate
    wire signed [31:0] sh3 = param3[95:64];

    wire signed [63:0] half = 64'sd1 <<< (sh3[5:0] - 6'd1);
    wire signed [63:0] acc_sh = (sh3 <= 0) ?(acc_r3 <<< (-sh3)) :
                                (acc_r3 >= 0) ? ((acc_r3 + half) >>> sh3[5:0]) :
                                                ((acc_r3 - half) >>> sh3[5:0]);

    wire signed [7:0] acc_sat = (acc_sh < -127) ? -8'sd127 : (acc_sh > 127) ? 8'sd127 : acc_sh[7:0]; 

    always @(posedge clk) begin
        if (!rst_n) begin
            valid_r1 <= 0;
            valid_r2 <= 0;
            valid_r3 <= 0;
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
            rq <= acc_sat;
            rq_valid <= valid_r3;
            rq_tag <= tag_r3;
        end
    end

endmodule
