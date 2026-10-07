`timescale 1ns / 1ps

// Parallel CNN Encoder : one CNN_Encoder (RX=1) per receiver, all RX run at the same time.
// Every encoder follows the same schedule (lockstep), so conv weight and requant parameter
// reads are the same for all RX and share one port. The GELU LUT address depends on data,
// so each RX has its own LUT read port.
module CNN_Encoder_Parallel #(
    parameter RX = 5,  // number of receivers
    // derived from RX, do not override
    parameter RX_W        = (RX > 1) ? $clog2(RX) : 1,
    parameter IN_BYTES    = RX * 3 * 128 * 10,     // input RX*3 ch x 128 x 10
    parameter IN_WADDR_W  = $clog2(IN_BYTES / 8),  // 64-bit word address
    parameter FEAT_ADDR_W = $clog2(RX * 128)       // Pool result RX x 1024 B, 64-bit word address
) (
    input  wire                     clk,
    input  wire                     rst_n,
    // TOP FSM
    input  wire                     enc_start,
    output wire                     enc_done,
    // from loader : same layout as the serial encoder (ch = rx + RX*ic, channel-major)
    input  wire                     in_we,
    input  wire [IN_WADDR_W - 1:0]  in_waddr,  // 64-bit word 0 ~ RX*480-1
    input  wire [            63:0]  in_wdata,
    // Loader RAM : conv weight / requant param shared by all RX
    output wire [             8:0]  conv_raddr,
    input  wire [           127:0]  conv_rdata,
    output wire [             8:0]  enc_param_raddr,
    input  wire [            95:0]  enc_param_rdata,  // {shift, mult, bias}
    // Loader RAM : GELU LUT, one read port per RX ({RX-1, ..., RX0})
    output wire [   RX * 10 - 1:0]  enc_lut_raddr,
    input  wire [    RX * 8 - 1:0]  enc_lut_rdata,
    input  wire [            31:0]  pool_mult,
    input  wire [            31:0]  pool_shift,
    // Flatten : byte = rx*1024 + oc*32 + oh*4 + ow
    input  wire [FEAT_ADDR_W - 1:0] feat_raddr,
    output wire [            63:0]  feat_rdata
);

    localparam CH_WORDS = 128 * 10 / 8;         // 160 words per channel
    localparam CH_W     = $clog2(3 * RX);       // channel index width
    localparam LOC_W    = $clog2(3 * CH_WORDS); // per-RX input word address (0 ~ 479)

    // ------------------------------------------------------------
    // input write routing : word -> channel -> (rx, ic) -> per-RX buffer
    // stage 1 : channel / offset, stage 2 : rx / local address
    // ------------------------------------------------------------
    reg              we_r1, we_r2;
    reg [CH_W - 1:0] ch_r1;
    reg [       7:0] off_r1;
    reg [      63:0] data_r1, data_r2;
    reg [RX_W - 1:0] rx_r2;
    reg [LOC_W - 1:0] loc_r2;

    always @(posedge clk) begin
        if (!rst_n) begin
            we_r1 <= 0;
            we_r2 <= 0;
        end else begin
            // stage 1
            we_r1   <= in_we;
            ch_r1   <= in_waddr / CH_WORDS;
            off_r1  <= in_waddr % CH_WORDS;
            data_r1 <= in_wdata;
            // stage 2
            we_r2   <= we_r1;
            rx_r2   <= ch_r1 % RX;
            loc_r2  <= (ch_r1 / RX) * CH_WORDS + off_r1;
            data_r2 <= data_r1;
        end
    end

    // ------------------------------------------------------------
    // encoders
    // ------------------------------------------------------------
    wire [      RX - 1:0] done;
    wire [  RX * 9 - 1:0] conv_raddr_all;
    wire [  RX * 9 - 1:0] param_raddr_all;
    wire [ RX * 64 - 1:0] feat_rdata_all;

    genvar r;
    generate
        for (r = 0; r < RX; r = r + 1) begin : g_rx
            CNN_Encoder #(
                .RX(1)
            ) u_enc (
                .clk            (clk),
                .rst_n          (rst_n),
                .enc_start      (enc_start),
                .enc_done       (done[r]),
                .in_we          (we_r2 && (rx_r2 == r)),
                .in_waddr       (loc_r2),
                .in_wdata       (data_r2),
                .conv_raddr     (conv_raddr_all[9*r +: 9]),
                .conv_rdata     (conv_rdata),
                .enc_param_raddr(param_raddr_all[9*r +: 9]),
                .enc_param_rdata(enc_param_rdata),
                .enc_lut_raddr  (enc_lut_raddr[10*r +: 10]),
                .enc_lut_rdata  (enc_lut_rdata[8*r +: 8]),
                .pool_mult      (pool_mult),
                .pool_shift     (pool_shift),
                .feat_raddr     (feat_raddr[6:0]),
                .feat_rdata     (feat_rdata_all[64*r +: 64])
            );
        end
    endgenerate

    // lockstep : every encoder issues the same weight / param address, use RX0's
    assign conv_raddr      = conv_raddr_all[8:0];
    assign enc_param_raddr = param_raddr_all[8:0];

    // all encoders finish in the same cycle
    assign enc_done = &done;

    // ------------------------------------------------------------
    // Pool result read : word = rx*128 + local, select RX one cycle later (rdata latency)
    // ------------------------------------------------------------
    wire [FEAT_ADDR_W - 1:0] feat_rx = feat_raddr >> 7;
    reg  [FEAT_ADDR_W - 1:0] feat_rx_r;

    always @(posedge clk) feat_rx_r <= feat_rx;

    assign feat_rdata = feat_rdata_all[64*feat_rx_r +: 64];

endmodule
