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

    reg signed [31:0] acc_r1;
    reg [95:0]        param_r1;
    reg               valid_r1;
    reg [TAG_WIDTH-1:0] tag_r1;

    reg signed [32:0] acc_r2;
    reg signed [31:0] mult_r2;
    reg signed [31:0] shift_r2;
    reg               valid_r2;
    reg [TAG_WIDTH-1:0] tag_r2;

    reg signed [64:0] acc_r3;
    reg signed [31:0] shift_r3;
    reg               valid_r3;
    reg [TAG_WIDTH-1:0] tag_r3;

    reg signed [64:0] acc_r4;
    reg signed [65:0] offset_r4;
    reg signed [31:0] shift_r4;
    reg               valid_r4;
    reg [TAG_WIDTH-1:0] tag_r4;

    reg signed [65:0] rounded_r5;
    reg signed [31:0] shift_r5;
    reg               valid_r5;
    reg [TAG_WIDTH-1:0] tag_r5;

    reg signed [65:0] shifted_r6;
    reg               valid_r6;
    reg [TAG_WIDTH-1:0] tag_r6;

    wire signed [31:0] bias_r1;
    wire signed [32:0] acc_ext;
    wire signed [32:0] bias_ext;
    wire signed [32:0] acc_bias;

    wire signed [64:0] acc_mult;

    wire signed [7:0] saturated;

    assign bias_r1  = $signed(param_r1[31:0]);

    assign acc_ext  = {acc_r1[31], acc_r1};
    assign bias_ext = {bias_r1[31], bias_r1};

    assign acc_bias = acc_ext + bias_ext;

    assign acc_mult = $signed(acc_r2) * $signed(mult_r2);

    assign saturated =
        (shifted_r6 > 66'sd127)  ? 8'sd127 :
        (shifted_r6 < -66'sd127) ? -8'sd127 :
                                   shifted_r6[7:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_r1     <= 32'sd0;
            param_r1   <= 96'd0;
            valid_r1   <= 1'b0;
            tag_r1     <= {TAG_WIDTH{1'b0}};

            acc_r2     <= 33'sd0;
            mult_r2    <= 32'sd0;
            shift_r2   <= 32'sd0;
            valid_r2   <= 1'b0;
            tag_r2     <= {TAG_WIDTH{1'b0}};

            acc_r3     <= 65'sd0;
            shift_r3   <= 32'sd0;
            valid_r3   <= 1'b0;
            tag_r3     <= {TAG_WIDTH{1'b0}};

            acc_r4     <= 65'sd0;
            offset_r4  <= 66'sd0;
            shift_r4   <= 32'sd0;
            valid_r4   <= 1'b0;
            tag_r4     <= {TAG_WIDTH{1'b0}};

            rounded_r5 <= 66'sd0;
            shift_r5   <= 32'sd0;
            valid_r5   <= 1'b0;
            tag_r5     <= {TAG_WIDTH{1'b0}};

            shifted_r6 <= 66'sd0;
            valid_r6   <= 1'b0;
            tag_r6     <= {TAG_WIDTH{1'b0}};

            rq          <= 8'd0;
            rq_valid    <= 1'b0;
            rq_tag      <= {TAG_WIDTH{1'b0}};
        end else begin

            acc_r1   <= $signed(acc);
            param_r1 <= param_rdata;
            valid_r1 <= acc_valid;
            tag_r1   <= acc_tag;

            acc_r2   <= acc_bias;
            mult_r2  <= $signed(param_r1[63:32]);
            shift_r2 <= $signed(param_r1[95:64]);
            valid_r2 <= valid_r1;
            tag_r2   <= tag_r1;

            acc_r3   <= acc_mult;
            shift_r3 <= shift_r2;
            valid_r3 <= valid_r2;
            tag_r3   <= tag_r2;

            acc_r4   <= acc_r3;
            shift_r4 <= shift_r3;
            valid_r4 <= valid_r3;
            tag_r4   <= tag_r3;

            if ((shift_r3 > 0) && (shift_r3 <= 65))
                offset_r4 <= 66'sd1 <<< (shift_r3 - 1);
            else
                offset_r4 <= 66'sd0;

            if (shift_r4 <= 0) begin
                rounded_r5 <= {{1{acc_r4[64]}}, acc_r4};
            end else if (shift_r4 <= 65) begin
                if (acc_r4 >= 0)
                    rounded_r5 <=
                        {{1{acc_r4[64]}}, acc_r4}
                        + offset_r4;
                else
                    rounded_r5 <=
                        {{1{acc_r4[64]}}, acc_r4}
                        + offset_r4
                        - 66'sd1;
            end else begin
                rounded_r5 <= {{1{acc_r4[64]}}, acc_r4};
            end

            shift_r5 <= shift_r4;
            valid_r5 <= valid_r4;
            tag_r5   <= tag_r4;

            if (shift_r5 > 65) begin
                shifted_r6 <= 66'sd0;
            end

            else if (shift_r5 > 0) begin
                shifted_r6 <= rounded_r5 >>> shift_r5;
            end

            else if (shift_r5 == 0) begin
                shifted_r6 <= rounded_r5;
            end

            else begin
                case (shift_r5)

                    -32'sd1: begin
                        if (rounded_r5 > 66'sd63)
                            shifted_r6 <= 66'sd127;
                        else if (rounded_r5 < -66'sd63)
                            shifted_r6 <= -66'sd127;
                        else
                            shifted_r6 <= rounded_r5 <<< 1;
                    end

                    -32'sd2: begin
                        if (rounded_r5 > 66'sd31)
                            shifted_r6 <= 66'sd127;
                        else if (rounded_r5 < -66'sd31)
                            shifted_r6 <= -66'sd127;
                        else
                            shifted_r6 <= rounded_r5 <<< 2;
                    end

                    -32'sd3: begin
                        if (rounded_r5 > 66'sd15)
                            shifted_r6 <= 66'sd127;
                        else if (rounded_r5 < -66'sd15)
                            shifted_r6 <= -66'sd127;
                        else
                            shifted_r6 <= rounded_r5 <<< 3;
                    end

                    -32'sd4: begin
                        if (rounded_r5 > 66'sd7)
                            shifted_r6 <= 66'sd127;
                        else if (rounded_r5 < -66'sd7)
                            shifted_r6 <= -66'sd127;
                        else
                            shifted_r6 <= rounded_r5 <<< 4;
                    end

                    -32'sd5: begin
                        if (rounded_r5 > 66'sd3)
                            shifted_r6 <= 66'sd127;
                        else if (rounded_r5 < -66'sd3)
                            shifted_r6 <= -66'sd127;
                        else
                            shifted_r6 <= rounded_r5 <<< 5;
                    end

                    -32'sd6: begin
                        if (rounded_r5 > 66'sd1)
                            shifted_r6 <= 66'sd127;
                        else if (rounded_r5 < -66'sd1)
                            shifted_r6 <= -66'sd127;
                        else
                            shifted_r6 <= rounded_r5 <<< 6;
                    end

                    default: begin
                        if (rounded_r5 > 0)
                            shifted_r6 <= 66'sd127;
                        else if (rounded_r5 < 0)
                            shifted_r6 <= -66'sd127;
                        else
                            shifted_r6 <= 66'sd0;
                    end

                endcase
            end

            valid_r6 <= valid_r5;
            tag_r6   <= tag_r5;

            rq       <= saturated;
            rq_valid <= valid_r6;
            rq_tag   <= tag_r6;
        end
    end

endmodule