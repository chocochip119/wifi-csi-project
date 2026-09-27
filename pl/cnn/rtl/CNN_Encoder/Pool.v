`timescale 1ns / 1ps
module Pool (
    input wire clk,
    input wire rst_n,
    input wire [7:0] pool_q,
    input wire pool_valid,
    input wire [18:0] pool_tag,  // {rx[1:0], layer, oc[4:0], h[6:0], w[3:0]}
    input wire [31:0] pool_mult,  // signed, LOAD 후 고정
    input wire [31:0] pool_shift,  // signed, LOAD 후 고정 (현재 blob: 31)
    input wire [8:0] feat_raddr,
    output reg [63:0] feat_rdata,
    output wire enc_done
);

    // tag
    wire [1:0] tag_rx = pool_tag[18:17];
    wire [4:0] tag_oc = pool_tag[15:11];
    wire [6:0] tag_h = pool_tag[10:4];
    wire [3:0] tag_w = pool_tag[3:0];

    wire [3:0] lane = tag_oc[3:0];  
    wire pass = tag_oc[4];
    wire [2:0] tag_oh = tag_h[6:4];
    wire [1:0] ow   = (tag_w < 3) ? 2'd0 : (tag_w < 5) ? 2'd1 : (tag_w < 8) ? 2'd2 : 2'd3;
    wire dual = (tag_w == 2) || (tag_w == 7); 
    wire [5:0] idx_a = {lane, ow}; 
    wire [5:0] idx_b = {lane, ow + 2'd1}; 

    wire first_a = (tag_h[3:0] == 0) && ((tag_w == 0) || (tag_w == 5));
    wire first_b = (tag_h[3:0] == 0);

    wire stripe_last = pool_valid && (tag_h[3:0] == 15) && (tag_w == 9) && (lane == 15);

    wire signed [15:0] q = {{8{pool_q[7]}}, pool_q};  // signed extension


    // while stripe, acc 
    reg signed [15:0] acc[0:63];

    always @(posedge clk) begin
        if (pool_valid) begin
            acc[idx_a] <= first_a ? q : acc[idx_a] + q;
            if (dual) acc[idx_b] <= first_b ? q : acc[idx_b] + q;
        end
    end

    // end stripe 
    reg signed [15:0] hold [0:63];
    reg         done_r0;
    reg [1:0] st_rx;
    reg st_pass;
    reg [2:0] st_oh;
    reg busy;
    reg [5:0] cidx;
    integer i;

    always @(posedge clk) begin
        if (!rst_n) begin
            done_r0 <= 0;
            busy <= 0;
            cidx <= 0;
        end else begin
            done_r0 <= stripe_last;
            if (stripe_last) begin
                st_rx <= tag_rx;
                st_pass <= pass;
                st_oh <= tag_oh;
            end
            if (done_r0) begin
                for (i = 0; i < 64; i = i + 1) hold[i] <= acc[i];
                busy <= 1'b1;
                cidx <= 0;
            end else if (busy) begin
                cidx <= cidx + 1;
                if (cidx == 63) busy <= 0;
            end
        end
    end

    // stage 1 : read hold
    // stage 2 : sum * pool_mult
    // stage 3 : round shift + saturation
    // stage 4 : /48 + clamp -> write result

    reg v_r1, v_r2, v_r3, v_r4;
    reg [5:0] idx_r1, idx_r2, idx_r3, idx_r4;
    reg signed [15:0] sum_r1;
    reg signed [47:0] prod_r2;
    reg signed [14:0] p_r3;
    reg [7:0] q_r4;

    // stage 3 
    wire signed [31:0] sh = pool_shift;
    wire signed [63:0] p64 = prod_r2;
    wire signed [63:0] half = 64'sd1 <<< (sh[5:0] - 6'd1);
    wire signed [63:0] rs = (sh <= 0) ? (p64 <<< (-sh)) : (p64 >= 0) ? ((p64 + half) >>> sh[5:0]) : ((p64 - half) >>> sh[5:0]);

    wire signed [14:0] p_sat = (rs > 8191) ? 15'sd8191 : (rs < - 8191) ? -15'sd8191 : rs[14:0];

    // stage 4
    wire signed [16:0] pp = p_r3;
    wire        [16:0] num = pp[16] ? (17'sd71 - pp) : (pp + 17'sd24);
    wire        [8:0] dq = (num * 5462) >> 18;
    wire signed [9:0] qs = pp[16] ? -$signed({1'b0, dq}) : $signed({1'b0, dq});
    wire        [7:0] q_clamp = (qs > 127) ? 8'd127 : (qs < -127) ? 8'h81 : qs[7:0];

    always @(posedge clk) begin
        if (!rst_n) begin
            v_r1 <= 0;
            v_r2 <= 0;
            v_r3 <= 0;
            v_r4 <= 0;
        end
        else begin
            // stage 1
            v_r1 <= busy;
            idx_r1 <= cidx;
            sum_r1 <= hold[cidx];
            // stage 2
            v_r2 <= v_r1;
            idx_r2 <= idx_r1;
            prod_r2 <= sum_r1 * $signed(pool_mult);
            // stage 3
            v_r3 <= v_r2;
            idx_r3 <= idx_r2;
            p_r3 <= p_sat;
            // stage 4
            v_r4 <= v_r3;
            idx_r4 <= idx_r3;
            q_r4 <= q_clamp;
        end
    end

    // result memory
    wire [11:0] wr_addr = {st_rx, st_pass, idx_r4[5:2], st_oh, idx_r4[1:0]};
    wire [63:0] wr_data64 = {8{q_r4}};
    wire [7:0] wr_be = 8'b1 << wr_addr[2:0];

    assign enc_done = v_r4 && (idx_r4 == 63) && (st_rx == 2) && st_pass && (st_oh == 7);

    reg [63:0] res_mem [0:383];
    integer k;

    always @(posedge clk) begin
        for (k = 0; k < 8; k = k + 1) 
            if (v_r4 && wr_be[k]) res_mem[wr_addr[11:3]][8*k +: 8] <= wr_data64[8*k +: 8];
        feat_rdata <= res_mem[feat_raddr];
    end

endmodule
