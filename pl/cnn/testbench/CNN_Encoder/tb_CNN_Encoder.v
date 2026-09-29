`timescale 1ns / 1ps

// CNN_Encoder 통합 테스트 : Conv1 → requant → GELU → Conv2 → requant → GELU → Pool
// RX 개 Pool 결과 RX*1024 B 를 int8 reference 와 비교, enc_done 1회 확인
// 벡터: python gen_CNN_Encoder.py <RX>  (enc_*.hex, numpy 필요), RX 는 아래 parameter 와 같게
module tb_CNN_Encoder;
    parameter RX = 3;
    localparam IN_WORDS = RX * 480, FEAT_WORDS = RX * 128;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg          enc_start = 0;
    wire         enc_done;
    reg          in_we = 0;
    reg  [$clog2(IN_WORDS) - 1:0] in_waddr = 0;
    reg  [ 63:0] in_wdata = 0;
    wire [  8:0] conv_raddr;
    reg  [127:0] conv_rdata;
    wire [  8:0] enc_param_raddr;
    reg  [ 95:0] enc_param_rdata;
    wire [  9:0] enc_lut_raddr;
    reg  [  7:0] enc_lut_rdata;
    reg  [ 31:0] pool_mult, pool_shift;
    reg  [ 31:0] pool_mem [0:1];
    reg  [$clog2(FEAT_WORDS) - 1:0] feat_raddr = 0;
    wire [ 63:0] feat_rdata;

    CNN_Encoder #(.RX(RX)) dut (
        .clk(clk), .rst_n(rst_n),
        .enc_start(enc_start), .enc_done(enc_done),
        .in_we(in_we), .in_waddr(in_waddr), .in_wdata(in_wdata),
        .conv_raddr(conv_raddr), .conv_rdata(conv_rdata),
        .enc_param_raddr(enc_param_raddr), .enc_param_rdata(enc_param_rdata),
        .enc_lut_raddr(enc_lut_raddr), .enc_lut_rdata(enc_lut_rdata),
        .pool_mult(pool_mult), .pool_shift(pool_shift),
        .feat_raddr(feat_raddr), .feat_rdata(feat_rdata)
    );

    // Loader 소유 RAM 모델 (동기 1-cycle)
    reg [127:0] w_mem   [0:332];
    reg [ 95:0] p_mem   [0:327];
    reg [  7:0] lut_mem [0:1023];
    reg [ 63:0] in_mem  [0:IN_WORDS - 1];
    reg [ 63:0] exp_mem [0:FEAT_WORDS - 1];

    always @(posedge clk) begin
        conv_rdata      <= w_mem[conv_raddr];
        enc_param_rdata <= p_mem[enc_param_raddr];
        enc_lut_rdata   <= lut_mem[enc_lut_raddr];
    end

    integer k, err = 0, done_cnt = 0, bad_byte = 0;
    always @(posedge clk) if (enc_done) done_cnt = done_cnt + 1;

    initial begin
        $readmemh("enc_wram.hex", w_mem);
        $readmemh("enc_param.hex", p_mem);
        $readmemh("enc_lut.hex", lut_mem);
        $readmemh("enc_in64.hex", in_mem);
        $readmemh("enc_feat.hex", exp_mem);
        $readmemh("enc_pool.hex", pool_mem);
        pool_mult  = pool_mem[0];
        pool_shift = pool_mem[1];

        repeat (5) @(posedge clk);
        rst_n <= 1;

        // 입력 버퍼 채우기 (RX*480 beat)
        for (k = 0; k < IN_WORDS; k = k + 1) begin
            @(posedge clk);
            in_we    <= 1;
            in_waddr <= k;
            in_wdata <= in_mem[k];
        end
        @(posedge clk) in_we <= 0;

        @(posedge clk) enc_start <= 1;
        @(posedge clk) enc_start <= 0;

        @(posedge clk);
        while (!enc_done) @(posedge clk);
        $display("enc_done at %0t", $time);
        repeat (20) @(posedge clk);

        // Pool 결과 읽기 (raddr 다음 cycle rdata)
        for (k = 0; k < FEAT_WORDS; k = k + 1) begin
            feat_raddr <= k;
            @(posedge clk);
            @(negedge clk);
            if (feat_rdata !== exp_mem[k]) begin
                err = err + 1;
                if (err <= 10) $display("MISMATCH word %0d got %h exp %h", k, feat_rdata, exp_mem[k]);
            end
            @(posedge clk);
        end
        $display("RX=%0d feat words checked=%0d errors=%0d enc_done pulses=%0d", RX, FEAT_WORDS, err, done_cnt);
        $finish;
    end

    initial begin
        #100_000_000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
