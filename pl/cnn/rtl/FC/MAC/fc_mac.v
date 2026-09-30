`timescale 1ns / 1ps

module fc_mac #(
    parameter integer ACC_WIDTH = 32,
    parameter integer TAG_WIDTH = 9
)(
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire [63:0]              act_data,
    input  wire [63:0]              weight_data,
    input  wire                     mac_valid,
    input  wire                     mac_first,
    input  wire                     mac_last,
    input  wire [TAG_WIDTH-1:0]     mac_tag,

    output reg  [ACC_WIDTH-1:0]     acc,
    output reg                      acc_valid,
    output reg  [TAG_WIDTH-1:0]     acc_tag
);
    // Input Register
    reg [63:0] act_r1;
    reg [63:0] weight_r1;
    reg        valid_r1;
    reg        first_r1;
    reg        last_r1;
    reg [TAG_WIDTH-1:0] tag_r1;

    wire signed [7:0] x0 = $signed(act_r1[7:0]);
    wire signed [7:0] x1 = $signed(act_r1[15:8]);
    wire signed [7:0] x2 = $signed(act_r1[23:16]);
    wire signed [7:0] x3 = $signed(act_r1[31:24]);
    wire signed [7:0] x4 = $signed(act_r1[39:32]);
    wire signed [7:0] x5 = $signed(act_r1[47:40]);
    wire signed [7:0] x6 = $signed(act_r1[55:48]);
    wire signed [7:0] x7 = $signed(act_r1[63:56]);

    wire signed [7:0] w0 = $signed(weight_r1[7:0]);
    wire signed [7:0] w1 = $signed(weight_r1[15:8]);
    wire signed [7:0] w2 = $signed(weight_r1[23:16]);
    wire signed [7:0] w3 = $signed(weight_r1[31:24]);
    wire signed [7:0] w4 = $signed(weight_r1[39:32]);
    wire signed [7:0] w5 = $signed(weight_r1[47:40]);
    wire signed [7:0] w6 = $signed(weight_r1[55:48]);
    wire signed [7:0] w7 = $signed(weight_r1[63:56]);

    // 8-Lane Multiply
    reg signed [15:0] p0_r2;
    reg signed [15:0] p1_r2;
    reg signed [15:0] p2_r2;
    reg signed [15:0] p3_r2;
    reg signed [15:0] p4_r2;
    reg signed [15:0] p5_r2;
    reg signed [15:0] p6_r2;
    reg signed [15:0] p7_r2;
    reg               valid_r2;
    reg               first_r2;
    reg               last_r2;
    reg [TAG_WIDTH-1:0] tag_r2;

    // Adder Tree
    wire signed [16:0] sum01 = p0_r2 + p1_r2;
    wire signed [16:0] sum23 = p2_r2 + p3_r2;
    wire signed [16:0] sum45 = p4_r2 + p5_r2;
    wire signed [16:0] sum67 = p6_r2 + p7_r2;

    wire signed [17:0] sum0123 = sum01 + sum23;
    wire signed [17:0] sum4567 = sum45 + sum67;
    wire signed [18:0] lane_sum = sum0123 + sum4567;

    reg signed [18:0] lane_sum_r3;
    reg               valid_r3;
    reg               first_r3;
    reg               last_r3;
    reg [TAG_WIDTH-1:0] tag_r3;

    // Accumulator
    reg signed [ACC_WIDTH-1:0] acc_reg;
    reg [TAG_WIDTH-1:0]        tag_reg;

    wire signed [ACC_WIDTH-1:0] lane_sum_ext =
        {{(ACC_WIDTH-19){lane_sum_r3[18]}}, lane_sum_r3};

    wire signed [ACC_WIDTH-1:0] next_acc =
        first_r3 ? lane_sum_ext : acc_reg + lane_sum_ext;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            act_r1      <= 0;
            weight_r1   <= 0;
            valid_r1    <= 0;
            first_r1    <= 0;
            last_r1     <= 0;
            tag_r1      <= 0;

            p0_r2       <= 0;
            p1_r2       <= 0;
            p2_r2       <= 0;
            p3_r2       <= 0;
            p4_r2       <= 0;
            p5_r2       <= 0;
            p6_r2       <= 0;
            p7_r2       <= 0;
            valid_r2    <= 0;
            first_r2    <= 0;
            last_r2     <= 0;
            tag_r2      <= 0;

            lane_sum_r3 <= 0;
            valid_r3    <= 0;
            first_r3    <= 0;
            last_r3     <= 0;
            tag_r3      <= 0;

            acc_reg     <= 0;
            tag_reg     <= 0;
            acc         <= 0;
            acc_valid   <= 0;
            acc_tag     <= 0;
        end else begin
            act_r1    <= act_data;
            weight_r1 <= weight_data;
            valid_r1  <= mac_valid;
            first_r1  <= mac_first;
            last_r1   <= mac_last;
            tag_r1    <= mac_tag;

            p0_r2    <= x0 * w0;
            p1_r2    <= x1 * w1;
            p2_r2    <= x2 * w2;
            p3_r2    <= x3 * w3;
            p4_r2    <= x4 * w4;
            p5_r2    <= x5 * w5;
            p6_r2    <= x6 * w6;
            p7_r2    <= x7 * w7;
            valid_r2 <= valid_r1;
            first_r2 <= first_r1;
            last_r2  <= last_r1;
            tag_r2   <= tag_r1;

            lane_sum_r3 <= lane_sum;
            valid_r3    <= valid_r2;
            first_r3    <= first_r2;
            last_r3     <= last_r2;
            tag_r3      <= tag_r2;

            acc_valid <= 1'b0;

            if (valid_r3) begin
                acc_reg <= next_acc;

                if (first_r3)
                    tag_reg <= tag_r3;

                if (last_r3) begin
                    acc       <= next_acc;
                    acc_valid <= 1'b1;
                    acc_tag   <= first_r3 ? tag_r3 : tag_reg;
                end
            end
        end
    end

endmodule
