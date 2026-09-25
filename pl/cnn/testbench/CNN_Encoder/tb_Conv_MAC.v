`timescale 1ns / 1ps

// Conv_MAC 단위 테스트 : 3 RX 전체 acc 184,320개 (값·tag·순서) 를 Python conv 결과와 비교
// 벡터: python gen_Conv_MAC.py  (conv_in.hex, conv_f1.hex, conv_wram.hex, conv_exp.hex)
module tb_Conv_MAC;
    localparam N = 184320;
    reg clk = 0, rst_n = 0, enc_start = 0, fmap1_last = 0;
    always #5 clk = ~clk;

    wire [13:0] raddr;  reg [7:0] rdata;
    wire [14:0] f_raddr; reg [7:0] f_rdata;
    wire [8:0] w_raddr; reg [127:0] w_rdata;
    wire [31:0] acc; wire acc_valid; wire [18:0] acc_tag;

    reg [7:0]   in_mem [0:11519];
    reg [7:0]   f1_mem [0:20479];
    reg [127:0] w_mem  [0:332];
    reg [50:0]  exp_   [0:N-1];

    Conv_MAC dut(.clk(clk), .rst_n(rst_n), .enc_start(enc_start), .fmap1_last(fmap1_last),
        .raddr(raddr), .rdata(rdata), .fmap1_raddr(f_raddr), .fmap1_rdata(f_rdata),
        .conv_raddr(w_raddr), .conv_rdata(w_rdata), .acc(acc), .acc_valid(acc_valid), .acc_tag(acc_tag));

    // 1-cycle sync RAMs
    always @(posedge clk) begin
        rdata   <= in_mem[raddr];
        f_rdata <= f1_mem[f_raddr];
        w_rdata <= w_mem[w_raddr];
    end

    integer e = 0, err = 0, l0_cnt = 0, bad_addr = 0;
    initial begin
        $readmemh("conv_in.hex", in_mem); $readmemh("conv_f1.hex", f1_mem);
        $readmemh("conv_wram.hex", w_mem); $readmemh("conv_exp.hex", exp_);
        repeat (3) @(posedge clk); rst_n <= 1;
        @(posedge clk) enc_start <= 1;
        @(posedge clk) enc_start <= 0;
        wait (e == N);
        repeat (50) @(posedge clk);
        $display("checked=%0d errors=%0d bad_addr=%0d state=%0d", e, err, bad_addr, dut.state);
        $finish;
    end

    // downstream 흉내: Conv1 출력 20480개 뒤 약간 늦게 fmap1_last 펄스
    always @(posedge clk) begin
        fmap1_last <= 0;
        if (acc_valid && !acc_tag[16]) begin
            l0_cnt = l0_cnt + 1;
            if (l0_cnt == 20480) begin
                l0_cnt = 0;
                repeat (30) @(posedge clk);
                fmap1_last <= 1;
            end
        end
    end

    always @(posedge clk) if (acc_valid) begin
        if ({acc_tag, acc} !== exp_[e]) begin
            err = err + 1;
            if (err <= 10) $display("MISMATCH #%0d got tag=%h acc=%0d  exp tag=%h acc=%0d",
                e, acc_tag, $signed(acc), exp_[e][50:32], $signed(exp_[e][31:0]));
        end
        e = e + 1;
    end

    // 사용 중인 주소 범위 체크
    always @(posedge clk) if (dut.s1_valid && !dut.s1_pad) begin
        if (!dut.s1_layer && raddr > 11519) bad_addr = bad_addr + 1;
        if ( dut.s1_layer && f_raddr > 20479) bad_addr = bad_addr + 1;
        if (w_raddr > 332) bad_addr = bad_addr + 1;
    end

    initial begin #50_000_000; $display("TIMEOUT e=%0d", e); $finish; end
endmodule
