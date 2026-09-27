`timescale 1ns / 1ps

// requant_stage 단위 테스트 : 5000개 {tag, acc} → rq / rq_tag 를 reference 식과 비교
// 벡터: python gen_requant_stage.py  (rq_param.hex, rq_vec.hex, rq_exp.hex)
module tb_requant_stage;
    reg clk=0, rst_n=0; always #5 clk=~clk;
    reg [31:0] acc; reg acc_valid=0; reg [18:0] acc_tag=0;
    wire [8:0] raddr; reg [95:0] rdata;
    wire [7:0] rq; wire rq_valid; wire [18:0] rq_tag;
    reg [95:0] pmem [0:47];
    reg [50:0] vec [0:4999];
    reg [26:0] exp_ [0:4999];
    integer n=0, e=0, err=0, gaps=0;
    requant_stage dut(.clk(clk),.rst_n(rst_n),.acc(acc),.acc_valid(acc_valid),.acc_tag(acc_tag),
        .enc_param_raddr(raddr),.enc_param_rdata(rdata),.rq(rq),.rq_valid(rq_valid),.rq_tag(rq_tag));
    always @(posedge clk) rdata <= pmem[raddr];   // 1-cycle sync RAM
    initial begin
        $readmemh("rq_param.hex", pmem); $readmemh("rq_vec.hex", vec); $readmemh("rq_exp.hex", exp_);
        repeat(3) @(posedge clk); rst_n <= 1;
        while (n < 5000) begin
            @(posedge clk);
            if ($random % 4 == 0) begin acc_valid <= 0; acc <= 32'hDEADBEEF; end   // bubbles
            else begin acc_valid <= 1; {acc_tag, acc} <= vec[n]; n = n + 1; end
        end
        @(posedge clk) acc_valid <= 0;
        repeat(10) @(posedge clk);
        $display("checked=%0d errors=%0d", e, err); $finish;
    end
    always @(posedge clk) if (rst_n && rq_valid) begin
        if ({rq_tag, rq} !== exp_[e][26:0]) begin
            err = err + 1;
            if (err <= 10) $display("MISMATCH #%0d tag=%h rq=%0d exp=%0d", e, rq_tag, $signed(rq), $signed(exp_[e][7:0]));
        end
        e = e + 1;
    end
endmodule
