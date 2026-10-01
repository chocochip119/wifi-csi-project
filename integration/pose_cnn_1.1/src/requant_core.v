`timescale 1ns / 1ps

module requant_core #(
    parameter integer TAG_WIDTH = 9
)(
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire [31:0]              acc,
    input  wire                     acc_valid,
    input  wire [TAG_WIDTH-1:0]     acc_tag,
    input  wire [95:0]              param_rdata,

    output reg  [7:0]               rq,
    output reg                      rq_valid,
    output reg  [TAG_WIDTH-1:0]     rq_tag
);
    // Pipeline Registers
    reg signed [31:0] acc_r1;
    reg               valid_r1;
    reg [TAG_WIDTH-1:0] tag_r1;

    reg signed [32:0] acc_r2;
    reg               valid_r2;
    reg [TAG_WIDTH-1:0] tag_r2;
    reg [95:0]        param_r2;

    reg signed [64:0] acc_r3;
    reg signed [31:0] shift_r3;
    reg               valid_r3;
    reg [TAG_WIDTH-1:0] tag_r3;

    reg signed [64:0] acc_r4;
    reg signed [64:0] offset_r4;
    reg signed [31:0] shift_r4;
    reg               valid_r4;
    reg [TAG_WIDTH-1:0] tag_r4;

    reg signed [64:0] rounded_r5;
    reg signed [31:0] shift_r5;
    reg               valid_r5;
    reg [TAG_WIDTH-1:0] tag_r5;

    reg signed [64:0] shifted_r6;
    reg               valid_r6;
    reg [TAG_WIDTH-1:0] tag_r6;

    // Requant Arithmetic
    wire signed [31:0] bias_s1  = $signed(param_rdata[31:0]);
    wire signed [32:0] acc_ext  = {acc_r1[31], acc_r1};
    wire signed [32:0] bias_ext = {bias_s1[31], bias_s1};
    wire signed [32:0] acc_bias = acc_ext + bias_ext;

    wire signed [31:0] mult_s2  = $signed(param_r2[63:32]);
    wire signed [64:0] acc_mult = acc_r2 * mult_s2;

    wire signed [7:0] saturated =
        (shifted_r6 > 65'sd127)  ? 8'sd127 :
        (shifted_r6 < -65'sd127) ? -8'sd127 :
                                   shifted_r6[7:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_r1     <= 0;
            valid_r1   <= 0;
            tag_r1     <= 0;

            acc_r2     <= 0;
            valid_r2   <= 0;
            tag_r2     <= 0;
            param_r2   <= 0;

            acc_r3     <= 0;
            shift_r3   <= 0;
            valid_r3   <= 0;
            tag_r3     <= 0;

            acc_r4     <= 0;
            offset_r4  <= 0;
            shift_r4   <= 0;
            valid_r4   <= 0;
            tag_r4     <= 0;

            rounded_r5 <= 0;
            shift_r5   <= 0;
            valid_r5   <= 0;
            tag_r5     <= 0;

            shifted_r6 <= 0;
            valid_r6   <= 0;
            tag_r6     <= 0;

            rq          <= 0;
            rq_valid    <= 0;
            rq_tag      <= 0;
        end else begin
            acc_r1   <= $signed(acc);
            valid_r1 <= acc_valid;
            tag_r1   <= acc_tag;

            acc_r2   <= acc_bias;
            valid_r2 <= valid_r1;
            tag_r2   <= tag_r1;
            param_r2 <= param_rdata;

            acc_r3   <= acc_mult;
            shift_r3 <= $signed(param_r2[95:64]);
            valid_r3 <= valid_r2;
            tag_r3   <= tag_r2;

            acc_r4   <= acc_r3;
            shift_r4 <= shift_r3;
            valid_r4 <= valid_r3;
            tag_r4   <= tag_r3;

            if (shift_r3 > 0)
                offset_r4 <= 65'sd1 <<< (shift_r3 - 1);
            else
                offset_r4 <= 65'sd0;

            if (shift_r4 <= 0)
                rounded_r5 <= acc_r4;
            else if (acc_r4 >= 0)
                rounded_r5 <= acc_r4 + offset_r4;
            else
                // reference round_shift_signed: (v - 2^(s-1)) >> s for v < 0
                rounded_r5 <= acc_r4 - offset_r4;

            shift_r5 <= shift_r4;
            valid_r5 <= valid_r4;
            tag_r5   <= tag_r4;

            if (shift_r5 <= 0)
                shifted_r6 <= rounded_r5 <<< (-shift_r5);
            else
                shifted_r6 <= rounded_r5 >>> shift_r5;

            valid_r6 <= valid_r5;
            tag_r6   <= tag_r5;

            rq       <= saturated;
            rq_valid <= valid_r6;
            rq_tag   <= tag_r6;
        end
    end

endmodule
