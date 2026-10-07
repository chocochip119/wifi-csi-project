`timescale 1ns / 1ps

module gelu_core #(
    parameter integer TAG_WIDTH = 9
)(
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire [7:0]               rq,
    input  wire                     rq_valid,
    input  wire [TAG_WIDTH-1:0]     rq_tag,

    input  wire [1:0]               table_sel,
    output wire [9:0]               lut_raddr,
    input  wire [7:0]               lut_rdata,

    output wire [7:0]               gelu_q,
    output wire                     gelu_valid,
    output wire [TAG_WIDTH-1:0]     gelu_tag
);
    // INT8 Offset-Binary LUT Index
    wire [7:0] lut_index = {~rq[7], rq[6:0]};

    assign lut_raddr = {table_sel, lut_index};

    // LUT Read Delay
    reg                    valid_d1;
    reg [TAG_WIDTH-1:0]    tag_d1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_d1 <= 1'b0;
            tag_d1   <= {TAG_WIDTH{1'b0}};
        end else begin
            valid_d1 <= rq_valid;
            tag_d1   <= rq_tag;
        end
    end

    assign gelu_q     = lut_rdata;
    assign gelu_valid = valid_d1;
    assign gelu_tag   = tag_d1;

endmodule
