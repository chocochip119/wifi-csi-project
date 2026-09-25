
module gelu_stage (
    input wire clk,
    input wire rst_n,
    input wire [7:0] rq,
    input wire rq_valid,
    input wire [18:0] rq_tag,  // {rx[1:0], layer, oc[4:0], h[6:0], w[3:0]}
    output wire [9:0] enc_lut_raddr,
    input wire [7:0] enc_lut_rdata,
    output wire fmap1_we,
    output wire [14:0] fmap1_waddr,
    output wire [7:0] fmap1_wdata,
    output wire fmap1_last,
    output wire [7:0] pool_q,
    output wire pool_valid,
    output wire [18:0] pool_tag
);

    // stage 0 : get rq, rq_valid
    // stage 1 : get LUT rdata

    reg [7:0] rq_r0;
    reg rq_valid_r0, rq_valid_r1;
    reg [18:0] rq_tag_r0, rq_tag_r1;

    always @(posedge clk) begin
        if (!rst_n) begin
            rq_r0 <= 0;
            rq_valid_r0 <= 0;
            rq_valid_r1 <= 0;
            rq_tag_r0 <= 0;
            rq_tag_r1 <= 0;
        end else begin
            // stage 0 
            rq_r0 <= rq;
            rq_valid_r0 <= rq_valid;
            rq_tag_r0 <= rq_tag;
            // stage 1
            rq_valid_r1 <= rq_valid_r0;
            rq_tag_r1 <= rq_tag_r0;
        end
    end

    // stage 0
    wire tag0_layer = rq_tag_r0[16];
    assign enc_lut_raddr = {1'b0, tag0_layer, ~rq_r0[7], rq_r0[6:0]};

    // stage 1
    wire tag1_layer = rq_tag_r1[16];
    wire [4:0] tag1_oc = rq_tag_r1[15:11];
    wire [6:0] tag1_h = rq_tag_r1[10:4];
    wire [3:0] tag1_w = rq_tag_r1[3:0];

    wire [10:0] row1 = {tag1_oc[3:0], tag1_h};

    wire last = (tag1_oc == 5'd15) && (tag1_h == 7'd127) && (tag1_w == 4'd9);

    // Conv1, to fmap1_buf
    assign fmap1_we = rq_valid_r1 & ~tag1_layer;
    assign fmap1_waddr = ({row1, 3'b000} + {row1, 1'b0}) + tag1_w;
    assign fmap1_wdata = enc_lut_rdata;
    assign fmap1_last = fmap1_we & last;

    // Conv2, to Pool
    assign pool_valid = rq_valid_r1 & tag1_layer;
    assign pool_q = enc_lut_rdata;
    assign pool_tag = rq_tag_r1;

endmodule
