`timescale 1ns / 1ps

module Conv_MAC #(
    parameter RX = 5,  // number of receivers
    // derived from RX, do not override
    parameter RX_W       = (RX > 1) ? $clog2(RX) : 1,
    parameter TAG_W      = RX_W + 17,
    parameter IN_RADDR_W = $clog2(RX * 3 * 128 * 10)
) (
    input wire clk,
    input wire rst_n,
    input wire enc_start,
    input wire fmap1_last,
    output wire [IN_RADDR_W - 1:0] raddr,
    input wire [7:0] rdata,
    output wire [14:0] fmap1_raddr,
    input wire [7:0] fmap1_rdata,
    output wire [8:0] conv_raddr,
    input wire [127:0] conv_rdata,
    output wire [31:0] acc,
    output wire acc_valid,
    output wire [TAG_W - 1:0] acc_tag  // {rx[RX_W-1:0], layer, oc[4:0], h[6:0], w[3:0]};
);

    localparam IDLE = 0, CONV1 = 1, WAIT_FMAP1 = 2, CONV2_0 = 3, CONV2_1 = 4;

    localparam LANES = 16;
    localparam WIDTH = 10, HEIGHT = 128;

    // Conv1
    localparam C1_IC = 3, C1_KH = 5, C1_KW = 3, C1_TAPS = 45, C1_PAD_H = 2, C1_PAD_W = 1;
    localparam C1_WBASE = 0;

    // Conv2
    localparam C2_IC = 16, C2_KH = 3, C2_KW = 3, C2_TAPS = 144, C2_PAD_H = 1, C2_PAD_W = 1;
    localparam C2_WBASE = 45;

    // state : fsm, counter, tap info
    reg [2:0] state, n_state;
    reg [RX_W - 1:0] rx_cnt, n_rx_cnt;
    reg [7:0] tap_cnt, n_tap_cnt;  // max : 143
    reg [6:0] h_cnt, n_h_cnt;  // 0 ~ 127
    reg [3:0] w_cnt, n_w_cnt;  // 0 ~ 9
    reg [3:0] ic_cnt, n_ic_cnt;
    reg [2:0] kh_cnt, n_kh_cnt;
    reg [1:0] kw_cnt, n_kw_cnt;

    // current layer info 
    wire       cur_layer = (state == CONV2_0) || (state == CONV2_1);
    wire       cur_pass = (state == CONV2_1);
    wire [3:0] cur_ic_max = cur_layer ? C2_IC - 1 : C1_IC - 1;
    wire [2:0] cur_kh_max = cur_layer ? C2_KH - 1 : C1_KH - 1;
    wire [7:0] cur_tap_max = cur_layer ? C2_TAPS - 1 : C1_TAPS - 1;
    wire [2:0] cur_pad_h = cur_layer ? C2_PAD_H : C1_PAD_H;

    wire       conv_run = (state == CONV1) || (state == CONV2_0) || (state == CONV2_1);
    wire       tap_last = (tap_cnt == cur_tap_max);

    // tap -> input coordinate (activation = 0 in padding)
    wire signed [8:0] ih = {2'b00, h_cnt} + kh_cnt - cur_pad_h;  // -2 ~ 131
    wire signed [5:0] iw = {2'b00, w_cnt} + kw_cnt - C1_PAD_W;   // -1 ~ 10
    wire       pad = (ih < 0) || (ih > HEIGHT - 1) || (iw < 0) || (iw > WIDTH - 1);

    // input channel = rx + RX*ic (channels interleaved across RX)
    wire [IN_RADDR_W - 1:0] in_row  = ((rx_cnt + ic_cnt * RX) << 7) + ih[6:0];  // (rx + RX*ic)*128 + ih
    wire [IN_RADDR_W - 1:0] in_addr = in_row * WIDTH + iw[3:0];
    wire [10:0] f_row   = {ic_cnt, 7'd0} + ih[6:0];                // ic*128 + ih
    wire [14:0] f_addr  = f_row * WIDTH + iw[3:0];
    wire [8:0]  w_addr  = cur_layer ? (C2_WBASE + (cur_pass ? C2_TAPS : 0) + tap_cnt) : (C1_WBASE + tap_cnt);

    // for output 
    reg [31:0] acc_r, n_acc_r;
    reg acc_valid_r, n_acc_valid_r;
    reg [TAG_W - 1:0] acc_tag_r, n_acc_tag_r;

    // read address (registered)
    reg [IN_RADDR_W - 1:0] raddr_r, n_raddr_r;  // input buffer (Conv1)
    reg [14:0] fmap1_raddr_r, n_fmap1_raddr_r;  // fmap1 buffer (Conv2)
    reg [8:0] conv_raddr_r, n_conv_raddr_r;  // Conv weight RAM

    assign acc         = acc_r;
    assign acc_valid   = acc_valid_r;
    assign acc_tag     = acc_tag_r;

    assign raddr       = raddr_r;
    assign fmap1_raddr = fmap1_raddr_r;
    assign conv_raddr  = conv_raddr_r;

    // ------------------------------------------------------------
    // tap info pipeline
    // s1 : same cycle as address registers
    // s2 : RAM read data valid (1-cycle sync RAM)
    // s3 : product (prod_r) registered
    // ------------------------------------------------------------
    reg       s1_valid, s1_pad, s1_first, s1_last, s1_layer, s1_pass;
    reg [RX_W - 1:0] s1_rx;
    reg [6:0] s1_h;
    reg [3:0] s1_w;
    reg       s2_valid, s2_pad, s2_first, s2_last, s2_layer, s2_pass;
    reg [RX_W - 1:0] s2_rx;
    reg [6:0] s2_h;
    reg [3:0] s2_w;
    reg       s3_valid, s3_first, s3_last, s3_layer, s3_pass;
    reg [RX_W - 1:0] s3_rx;
    reg [6:0] s3_h;
    reg [3:0] s3_w;

    always @(posedge clk) begin
        if (!rst_n) begin
            s1_valid <= 0;
            s2_valid <= 0;
            s3_valid <= 0;
        end else begin
            s1_valid <= conv_run;
            s1_pad   <= pad;
            s1_first <= (tap_cnt == 0);
            s1_last  <= tap_last;
            s1_layer <= cur_layer;
            s1_pass  <= cur_pass;
            s1_rx    <= rx_cnt;
            s1_h     <= h_cnt;
            s1_w     <= w_cnt;

            s2_valid <= s1_valid;
            s2_pad   <= s1_pad;
            s2_first <= s1_first;
            s2_last  <= s1_last;
            s2_layer <= s1_layer;
            s2_pass  <= s1_pass;
            s2_rx    <= s1_rx;
            s2_h     <= s1_h;
            s2_w     <= s1_w;

            s3_valid <= s2_valid;
            s3_first <= s2_first;
            s3_last  <= s2_last;
            s3_layer <= s2_layer;
            s3_pass  <= s2_pass;
            s3_rx    <= s2_rx;
            s3_h     <= s2_h;
            s3_w     <= s2_w;
        end
    end

    // ------------------------------------------------------------
    // 16-lane MAC : 1 activation x 16 weights (lane = oc)
    // ------------------------------------------------------------
    wire [7:0] act = s2_pad ? 8'd0 : (s2_layer ? fmap1_rdata : rdata);
    wire [32*LANES-1:0] out_flat;

    genvar l;
    generate
        for (l = 0; l < LANES; l = l + 1) begin : g_lane
            reg signed [31:0] lane_acc;
            reg signed [31:0] lane_out;
            reg signed [15:0] prod_r;
            wire signed [15:0] prod = $signed(act) * $signed(conv_rdata[8*l +: 8]);
            wire signed [31:0] sum  = (s3_first ? 32'sd0 : lane_acc) + prod_r;

            always @(posedge clk) begin
                if (s2_valid) prod_r <= prod;              // s2 : multiply
                if (s3_valid) lane_acc <= sum;             // s3 : accumulate
                if (s3_valid && s3_last) lane_out <= sum;  // position done -> output buffer
            end

            assign out_flat[32*l +: 32] = lane_out;
        end
    endgenerate

    // ------------------------------------------------------------
    // serialize output : 16 results, lane 0 -> 15, one per cycle
    // (45 / 144 taps > 16 cycles, so it can overlap the next position)
    // ------------------------------------------------------------
    reg       drain_busy;
    reg [3:0] drain_cnt;
    reg       d_layer, d_pass;
    reg [RX_W - 1:0] d_rx;
    reg [6:0] d_h;
    reg [3:0] d_w;

    always @(posedge clk) begin
        if (!rst_n) begin
            drain_busy <= 0;
            drain_cnt  <= 0;
        end else begin
            if (s3_valid && s3_last) begin
                drain_busy <= 1;
                drain_cnt  <= 0;
                d_layer    <= s3_layer;
                d_pass     <= s3_pass;
                d_rx       <= s3_rx;
                d_h        <= s3_h;
                d_w        <= s3_w;
            end else if (drain_busy) begin
                drain_cnt <= drain_cnt + 1;
                if (drain_cnt == LANES - 1) drain_busy <= 0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state         <= IDLE;
            rx_cnt        <= 0;
            tap_cnt       <= 0;
            h_cnt         <= 0;
            w_cnt         <= 0;
            ic_cnt        <= 0;
            kh_cnt        <= 0;
            kw_cnt        <= 0;
            acc_r         <= 0;
            acc_valid_r   <= 0;
            acc_tag_r     <= 0;
            raddr_r       <= 0;
            fmap1_raddr_r <= 0;
            conv_raddr_r  <= 0;
        end else begin
            state         <= n_state;
            rx_cnt        <= n_rx_cnt;
            tap_cnt       <= n_tap_cnt;
            h_cnt         <= n_h_cnt;
            w_cnt         <= n_w_cnt;
            ic_cnt        <= n_ic_cnt;
            kh_cnt        <= n_kh_cnt;
            kw_cnt        <= n_kw_cnt;
            acc_r         <= n_acc_r;
            acc_valid_r   <= n_acc_valid_r;
            acc_tag_r     <= n_acc_tag_r;
            raddr_r       <= n_raddr_r;
            fmap1_raddr_r <= n_fmap1_raddr_r;
            conv_raddr_r  <= n_conv_raddr_r;
        end
    end

    always @(*) begin
        n_state         = state;
        n_rx_cnt        = rx_cnt;
        n_tap_cnt       = tap_cnt;
        n_h_cnt         = h_cnt;
        n_w_cnt         = w_cnt;
        n_ic_cnt        = ic_cnt;
        n_kh_cnt        = kh_cnt;
        n_kw_cnt        = kw_cnt;
        n_acc_r         = out_flat[32*drain_cnt +: 32];
        n_acc_valid_r   = drain_busy;
        n_acc_tag_r     = {d_rx, d_layer, d_pass, drain_cnt, d_h, d_w};
        n_raddr_r       = raddr_r;
        n_fmap1_raddr_r = fmap1_raddr_r;
        n_conv_raddr_r  = conv_raddr_r;
        case (state)
            IDLE: begin
                if (enc_start) begin
                    n_state   = CONV1;
                    n_rx_cnt  = 0;
                    n_tap_cnt = 0;
                    n_h_cnt   = 0;
                    n_w_cnt   = 0;
                    n_ic_cnt  = 0;
                    n_kh_cnt  = 0;
                    n_kw_cnt  = 0;
                end
            end
            CONV1, CONV2_0, CONV2_1: begin
                // read current tap
                n_raddr_r       = in_addr;
                n_fmap1_raddr_r = f_addr;
                n_conv_raddr_r  = w_addr;

                // tap order : ic -> kh -> kw  (tap = (ic*KH + kh)*KW + kw)
                if (kw_cnt == C1_KW - 1) begin
                    n_kw_cnt = 0;
                    if (kh_cnt == cur_kh_max) begin
                        n_kh_cnt = 0;
                        n_ic_cnt = (ic_cnt == cur_ic_max) ? 4'd0 : ic_cnt + 1;
                    end else begin
                        n_kh_cnt = kh_cnt + 1;
                    end
                end else begin
                    n_kw_cnt = kw_cnt + 1;
                end

                // position order : w -> h
                if (tap_last) begin
                    n_tap_cnt = 0;
                    if (w_cnt == WIDTH - 1) begin
                        n_w_cnt = 0;
                        if (h_cnt == HEIGHT - 1) begin
                            n_h_cnt = 0;
                            case (state)
                                CONV1:   n_state = WAIT_FMAP1;
                                CONV2_0: n_state = CONV2_1;
                                default: begin  // CONV2_1
                                    if (rx_cnt == RX - 1) begin
                                        n_state = IDLE;
                                    end else begin
                                        n_rx_cnt = rx_cnt + 1;
                                        n_state  = CONV1;
                                    end
                                end
                            endcase
                        end else begin
                            n_h_cnt = h_cnt + 1;
                        end
                    end else begin
                        n_w_cnt = w_cnt + 1;
                    end
                end else begin
                    n_tap_cnt = tap_cnt + 1;
                end
            end
            WAIT_FMAP1: begin
                if (fmap1_last) begin
                    n_state = CONV2_0;
                end
            end
            default: n_state = IDLE;
        endcase
    end

endmodule