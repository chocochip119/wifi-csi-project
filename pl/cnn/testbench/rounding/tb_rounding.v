`timescale 1ns/1ps
module tb_rounding;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;
    reg [31:0] acc=0;
    reg valid=0;
    reg [18:0] tag=0;
    wire [8:0] addr;
    reg [95:0] params [0:47], data;
    reg [50:0] vectors [0:7999];
    reg [26:0] expected [0:7999];
    wire [7:0] enc_q, fc_q;
    wire enc_v, fc_v;
    wire [18:0] enc_tag, fc_tag;
    integer n=0, enc_count=0, fc_count=0;
    requant_stage enc(.clk(clk),.rst_n(rst_n),.acc(acc),.acc_valid(valid),.acc_tag(tag),
        .enc_param_raddr(addr),.enc_param_rdata(data),.rq(enc_q),.rq_valid(enc_v),.rq_tag(enc_tag));
    requant_core #(.TAG_WIDTH(19)) fc(.clk(clk),.rst_n(rst_n),.acc(acc),.acc_valid(valid),
        .acc_tag(tag),.param_rdata(data),.rq(fc_q),.rq_valid(fc_v),.rq_tag(fc_tag));
    always @(posedge clk) data <= params[addr];
    always @(negedge clk) begin
        if (rst_n && enc_v) begin
            if (enc_count >= 8000 || {enc_tag,enc_q} !== expected[enc_count])
                $fatal(1,"Encoder mismatch %0d got=%h expected=%h",enc_count,{enc_tag,enc_q},expected[enc_count]);
            enc_count=enc_count+1;
        end
        if (rst_n && fc_v) begin
            if (fc_count >= 8000 || {fc_tag,fc_q} !== expected[fc_count])
                $fatal(1,"FC mismatch %0d got=%h expected=%h",fc_count,{fc_tag,fc_q},expected[fc_count]);
            fc_count=fc_count+1;
        end
    end
    initial begin
        $readmemh("params.hex",params);
        $readmemh("vectors.hex",vectors);
        $readmemh("expected.hex",expected);
        repeat(3) @(posedge clk);
        rst_n <= 1;
        while(n < 8000) begin
            @(posedge clk);
            if (n % 7 == 0 && valid) valid <= 0;
            else begin valid <= 1; {tag,acc} <= vectors[n]; n=n+1; end
        end
        @(posedge clk) valid <= 0;
        repeat(12) @(posedge clk);
        if (enc_count != 8000 || fc_count != 8000) $fatal(1,"missing output");
        $display("PASS independent Encoder=%0d FC=%0d (sync BRAM, bubbles)",enc_count,fc_count);
        $finish;
    end
    initial begin #200000; $fatal(1,"timeout"); end
endmodule
