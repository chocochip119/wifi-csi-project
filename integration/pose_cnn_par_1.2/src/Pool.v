`timescale 1ns / 1ps

module Pool #(
    parameter RX = 3,  // number of receivers
    // derived from RX, do not override
    parameter RX_W        = (RX > 1) ? $clog2(RX) : 1,
    parameter TAG_W       = RX_W + 17,
    parameter FEAT_ADDR_W = $clog2(RX * 128)  // result RX x 1024 B = RX*128 64-bit words
) (
    input wire clk,
    input wire rst_n,
    input wire [7:0] pool_q,
    input wire pool_valid,
    input wire [TAG_W - 1:0] pool_tag,  // {rx[RX_W-1:0], layer, oc[4:0], h[6:0], w[3:0]}
    input wire [31:0] pool_mult,  // signed, fixed after LOAD
    input wire [31:0] pool_shift,  // signed, fixed after LOAD (blob: 31)
    input wire [FEAT_ADDR_W - 1:0] feat_raddr,
    output reg [63:0] feat_rdata,
    output wire enc_done
);

    // tag
    wire [RX_W - 1:0] tag_rx = pool_tag[TAG_W - 1:17];
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

    // input stage : register the GELU LUT data and the decoded tag before the
    // accumulator (timing: LUT RAM output -> 64-entry read-modify-write).
    reg               in_valid, in_dual, in_first_a, in_first_b, in_last;
    reg         [5:0] in_idx_a, in_idx_b;
    reg         [7:0] in_q;
    reg [RX_W - 1:0]  in_rx;
    reg               in_pass;
    reg         [2:0] in_oh;

    always @(posedge clk) begin
        if (!rst_n) begin
            in_valid <= 0;
            in_last  <= 0;
        end else begin
            in_valid <= pool_valid;
            in_last  <= stripe_last;
        end
        in_q       <= pool_q;
        in_idx_a   <= idx_a;
        in_idx_b   <= idx_b;
        in_dual    <= dual;
        in_first_a <= first_a;
        in_first_b <= first_b;
        in_rx      <= tag_rx;
        in_pass    <= pass;
        in_oh      <= tag_oh;
    end

    wire signed [15:0] q = {{8{in_q[7]}}, in_q};  // signed extension


    // while stripe, acc
    // Read-modify-write split over two cycles (timing: 64:1 read mux + add +
    // write decode did not fit one cycle with five encoders).
    //   stage B : read acc[idx]      stage C : add / write
    // Safe without forwarding: consecutive inputs are consecutive lanes
    // (idx = {lane, ow} differ), and the same lane returns only at the next
    // Conv2 position, >= 128 cycles later.
    reg signed [15:0] acc[0:63];

    reg               b_valid, b_last, b_dual, b_first_a, b_first_b;
    reg         [5:0] b_idx_a, b_idx_b;
    reg signed [15:0] b_q, b_rd_a, b_rd_b;
    reg [RX_W - 1:0]  b_rx;
    reg               b_pass;
    reg         [2:0] b_oh;

    always @(posedge clk) begin
        if (!rst_n) begin
            b_valid <= 0;
            b_last  <= 0;
        end else begin
            b_valid <= in_valid;
            b_last  <= in_last;
        end
        b_idx_a   <= in_idx_a;
        b_idx_b   <= in_idx_b;
        b_dual    <= in_dual;
        b_first_a <= in_first_a;
        b_first_b <= in_first_b;
        b_q       <= q;
        b_rd_a    <= acc[in_idx_a];
        b_rd_b    <= acc[in_idx_b];
        b_rx      <= in_rx;
        b_pass    <= in_pass;
        b_oh      <= in_oh;
    end

    always @(posedge clk) begin
        if (b_valid) begin
            acc[b_idx_a] <= b_first_a ? b_q : b_rd_a + b_q;
            if (b_dual) acc[b_idx_b] <= b_first_b ? b_q : b_rd_b + b_q;
        end
    end

    // end stripe 
    reg signed [15:0] hold [0:63];
    reg         done_r0;
    reg [RX_W - 1:0] st_rx;
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
            done_r0 <= b_last;
            if (b_last) begin
                st_rx <= b_rx;
                st_pass <= b_pass;
                st_oh <= b_oh;
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

    // stage 1  : read hold
    // stage 2  : sum * pool_mult
    // stage 3a : round shift - add half / compare limits
    // stage 3  : round shift - shift / saturate
    // stage 4  : saturation
    // stage 5  : /48 (dq)
    // stage 6  : sign + clamp -> write result

    reg v_r1, v_r2, v_r3a, v_r3, v_r4, v_r5, v_r6;
    reg [5:0] idx_r1, idx_r2, idx_r3a, idx_r3, idx_r4, idx_r5, idx_r6;
    reg signed [15:0] sum_r1;
    reg signed [47:0] prod_r2;
    reg signed [63:0] rs_r3;
    reg signed [14:0] p_r4;
    reg [8:0] dq_r5;
    reg neg_r5;
    reg [7:0] q_r6;

    // stage 3 : round shift
    // pool_shift is fixed after LOAD, so everything derived from it alone is
    // decoded into registers here and kept out of the data path.
    wire signed [31:0] sh = pool_shift;
    reg               sh_big, sh_pos, sh_zero, sh_negall;  // >=49 / 1..48 / 0 / <=-13
    reg         [5:0] sh_r;                                // right shift 1..48
    reg         [3:0] nsh_r;                               // left shift 1..12
    reg signed [63:0] half_r, lim_r;

    always @(posedge clk) begin
        sh_big    <= (sh >= 49);
        sh_pos    <= (sh > 0) && (sh < 49);
        sh_zero   <= (sh == 0);
        sh_negall <= (sh <= -13);
        sh_r      <= sh[5:0];
        nsh_r     <= -sh[3:0];
        half_r    <= ((sh > 0) && (sh < 49)) ? (64'sd1 <<< (sh[5:0] - 6'd1)) : 64'sd0;
        lim_r     <= ((sh < 0) && (sh > -13)) ? (64'sd8191 >>> (-sh[3:0])) : 64'sd0;
    end

    // stage 3a : (p + half - [p<0]) and the left-shift saturation compares
    wire signed [63:0] p64 = prod_r2;
    reg signed [63:0] p_r3a, t_r3a;
    reg               gt_r3a, lt_r3a, pos_r3a, neg_r3a;

    always @(posedge clk) begin
        p_r3a   <= p64;
        t_r3a   <= p64 + half_r - ((p64 < 0) ? 64'sd1 : 64'sd0);
        gt_r3a  <= (p64 > lim_r);
        lt_r3a  <= (p64 < -lim_r);
        pos_r3a <= (p64 > 0);
        neg_r3a <= (p64 < 0);
    end

    // stage 3 : nearest, halfway away from zero (same result as before the split)
    reg signed [63:0] rs;
    always @* begin
        // prod_r2 is signed 48-bit, so shifts >= 49 always round to zero.
        if (sh_big) rs = 0;
        else if (sh_pos) rs = t_r3a >>> sh_r;
        else if (sh_zero) rs = p_r3a;
        else if (sh_negall)
            rs = pos_r3a ? 64'sd8191 : neg_r3a ? -64'sd8191 : 64'sd0;
        else if (gt_r3a) rs = 64'sd8191;
        else if (lt_r3a) rs = -64'sd8191;
        else rs = p_r3a <<< nsh_r;
    end

    // stage 4 : saturation
    wire signed [14:0] p_sat = (rs_r3 > 8191) ? 15'sd8191 : (rs_r3 < - 8191) ? -15'sd8191 : rs_r3[14:0];

    // stage 5 : /48
    wire signed [16:0] pp = p_r4;
    // Round the magnitude by /48, then restore the sign (ties away from zero).
    wire        [16:0] num = pp[16] ? (17'sd24 - pp) : (pp + 17'sd24);
    wire        [8:0] dq = (num * 5462) >> 18;

    // stage 6 : sign + clamp
    wire signed [9:0] qs = neg_r5 ? -$signed({1'b0, dq_r5}) : $signed({1'b0, dq_r5});
    wire        [7:0] q_clamp = (qs > 127) ? 8'd127 : (qs < -127) ? 8'h81 : qs[7:0];

    always @(posedge clk) begin
        if (!rst_n) begin
            v_r1 <= 0;
            v_r2 <= 0;
            v_r3a <= 0;
            v_r3 <= 0;
            v_r4 <= 0;
            v_r5 <= 0;
            v_r6 <= 0;
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
            // stage 3a (data registers in the block above)
            v_r3a <= v_r2;
            idx_r3a <= idx_r2;
            // stage 3
            v_r3 <= v_r3a;
            idx_r3 <= idx_r3a;
            rs_r3 <= rs;
            // stage 4
            v_r4 <= v_r3;
            idx_r4 <= idx_r3;
            p_r4 <= p_sat;
            // stage 5
            v_r5 <= v_r4;
            idx_r5 <= idx_r4;
            dq_r5 <= dq;
            neg_r5 <= pp[16];
            // stage 6
            v_r6 <= v_r5;
            idx_r6 <= idx_r5;
            q_r6 <= q_clamp;
        end
    end

    // result memory : byte addr = rx*1024 + oc*32 + oh*4 + ow
    wire [RX_W + 9:0] wr_addr = {st_rx, st_pass, idx_r6[5:2], st_oh, idx_r6[1:0]};
    wire [63:0] wr_data64 = {8{q_r6}};
    wire [7:0] wr_be = 8'b1 << wr_addr[2:0];

    assign enc_done = v_r6 && (idx_r6 == 63) && (st_rx == RX - 1) && st_pass && (st_oh == 7);

    reg [63:0] res_mem [0:RX * 128 - 1];
    integer k;

    always @(posedge clk) begin
        for (k = 0; k < 8; k = k + 1)
            if (v_r6 && wr_be[k]) res_mem[wr_addr[RX_W + 9:3]][8*k +: 8] <= wr_data64[8*k +: 8];
        feat_rdata <= res_mem[feat_raddr];
    end

endmodule
