`timescale 1ns / 1ps

module CNN_Encoder (
    input  wire         clk,
    input  wire         rst_n,
    // TOP FSM
    input  wire         enc_start,
    output wire         enc_done,
    // from loader 
    input  wire         in_we,
    input  wire [ 10:0] in_waddr,   // 64-bit word 0 ~ 1439
    input  wire [ 63:0] in_wdata,
    // Loader RAM
    output wire [  8:0] conv_raddr,
    input  wire [127:0] conv_rdata,
    output wire [  8:0] enc_param_raddr,
    input  wire [ 95:0] enc_param_rdata,  // {shift, mult, bias}
    output wire [  9:0] enc_lut_raddr,
    input  wire [  7:0] enc_lut_rdata,
    input  wire [ 31:0] pool_mult,
    input  wire [ 31:0] pool_shift,
    // Flatten
    input  wire [  8:0] feat_raddr,
    output wire [ 63:0] feat_rdata
);

    // input buffer <-> Conv MAC
    wire [13:0] in_raddr;
    wire [ 7:0] in_rdata;

    // fmap1 buffer <-> Conv MAC / gelu_stage
    wire [14:0] fmap1_raddr;
    wire [ 7:0] fmap1_rdata;
    wire        fmap1_we;
    wire [14:0] fmap1_waddr;
    wire [ 7:0] fmap1_wdata;
    wire        fmap1_last;

    // Conv MAC <-> requant_stage
    wire [31:0] acc;
    wire        acc_valid;
    wire [18:0] acc_tag;

    // requant_stage -> gelu_stage
    wire [ 7:0] rq;
    wire        rq_valid;
    wire [18:0] rq_tag;

    // gelu_stage -> Pool
    wire [ 7:0] pool_q;
    wire        pool_valid;
    wire [18:0] pool_tag;

    // input buffer
    Buffer #(
        .W_DATA_WIDTH(64),
        .R_DATA_WIDTH(8),
        .DEPTH_BYTE  (11520)
    ) u_input_buf (
        .clk  (clk),
        .we   (in_we),
        .waddr(in_waddr),
        .wdata(in_wdata),
        .raddr(in_raddr),
        .rdata(in_rdata)
    );

    Conv_MAC u_conv_mac (
        .clk        (clk),
        .rst_n      (rst_n),
        .enc_start  (enc_start),
        .fmap1_last (fmap1_last),
        .raddr      (in_raddr),
        .rdata      (in_rdata),
        .fmap1_raddr(fmap1_raddr),
        .fmap1_rdata(fmap1_rdata),
        .conv_raddr (conv_raddr),
        .conv_rdata (conv_rdata),
        .acc        (acc),
        .acc_valid  (acc_valid),
        .acc_tag    (acc_tag)
    );

    // Requant : acc + bias → × mult → round shift → [-127, 127]
    requant_stage u_enc_rq (
        .clk            (clk),
        .rst_n          (rst_n),
        .acc            (acc),
        .acc_valid      (acc_valid),
        .acc_tag        (acc_tag),
        .enc_param_raddr(enc_param_raddr),
        .enc_param_rdata(enc_param_rdata),
        .rq             (rq),
        .rq_valid       (rq_valid),
        .rq_tag         (rq_tag)
    );

    // GELU LUT : layer 0 → fmap1 buffer, layer 1 → Pool
    gelu_stage u_enc_gelu (
        .clk          (clk),
        .rst_n        (rst_n),
        .rq           (rq),
        .rq_valid     (rq_valid),
        .rq_tag       (rq_tag),
        .enc_lut_raddr(enc_lut_raddr),
        .enc_lut_rdata(enc_lut_rdata),
        .fmap1_we     (fmap1_we),
        .fmap1_waddr  (fmap1_waddr),
        .fmap1_wdata  (fmap1_wdata),
        .fmap1_last   (fmap1_last),
        .pool_q       (pool_q),
        .pool_valid   (pool_valid),
        .pool_tag     (pool_tag)
    );

    // fmap1 buffer 
    Buffer #(
        .W_DATA_WIDTH(8),
        .R_DATA_WIDTH(8),
        .DEPTH_BYTE  (20480)
    ) u_fmap1_buf (
        .clk  (clk),
        .we   (fmap1_we),
        .waddr(fmap1_waddr),
        .wdata(fmap1_wdata),
        .raddr(fmap1_raddr),
        .rdata(fmap1_rdata)
    );

    // Pool : AdaptiveAvgPool(8,4) + requant, 결과 3 RX × 1024 B
    Pool u_pool (
        .clk       (clk),
        .rst_n     (rst_n),
        .pool_q    (pool_q),
        .pool_valid(pool_valid),
        .pool_tag  (pool_tag),
        .pool_mult (pool_mult),
        .pool_shift(pool_shift),
        .feat_raddr(feat_raddr),
        .feat_rdata(feat_rdata),
        .enc_done  (enc_done)
    );

endmodule
