`timescale 1ns/1ps
module tb_fc_memories;
    reg clk=0, rst_n=0, we=0, wb=0, rb=0, pwe=0;
    reg [6:0] wa=0;
    reg [7:0] wd=0, pwd=0;
    reg [3:0] ra=0;
    reg [4:0] pwa=0, pra=0;
    wire [63:0] data;
    wire [7:0] pdata;
    reg [7:0] model[0:255], pmodel[0:23];
    reg [63:0] expected;
    reg [7:0] pexpected;
    reg [9:0] fa=0;
    reg [63:0] fd=0;
    wire [9:0] faddr;
    wire [63:0] fdata;
    integer i, b, seed=401, checks=0;
    always #5 clk=~clk;
    hidden_ram hidden(clk,rst_n,we,wb,wa,wd,rb,ra,data);
    pose_buffer pose(clk,rst_n,pwe,pwa,pwd,pra,pdata);
    flatten #(.RX_NUM(5),.ADDR_WIDTH(10)) flat(fa,fdata,faddr,fd);
    always @(posedge clk) begin
        expected=0;
        for(integer lane=0;lane<8;lane=lane+1) expected[8*lane+:8]=model[rb*128+ra*8+lane];
        pexpected=pmodel[pra];
        if(rst_n && we) model[wb*128+wa]=wd;
        if(rst_n && pwe) pmodel[pwa]=pwd;
        #1;
        if(!rst_n) begin
            if(data!==0 || pdata!==0) $fatal(1,"RAM reset outputs");
        end else begin
            if(data !== expected || pdata !== pexpected) $fatal(1,"RAM read-first/bank/byte order mismatch");
            checks=checks+1;
        end
    end
    initial begin
        if ($test$plusargs("waves")) begin $dumpfile("tb_fc_memories.vcd"); $dumpvars(0,tb_fc_memories); end
        // Do not assume reset clears BRAM: unknown unwritten bytes are modeled as X.
        repeat(3) @(negedge clk); rst_n=1;
        for(b=0;b<2;b=b+1) for(i=0;i<128;i=i+1) begin
            @(negedge clk); we=1; wb=b; wa=i; wd=i*11+b*53; rb=b; ra=i/8;
            pwe=i<24; pwa=i%24; pwd=i*7;
        end
        for(i=0;i<3000;i=i+1) begin
            @(negedge clk); we=$random(seed)&1; wb=$random(seed)&1; wa=$random(seed);
            wd=$random(seed); rb=$random(seed)&1; ra=$random(seed);
            pwe=$random(seed)&1; pwa=($random(seed)&32'h7fffffff)%24;
            pwd=$random(seed); pra=($random(seed)&32'h7fffffff)%24;
            fa=i%640; fd={$random(seed),$random(seed)};
            #1; if(faddr !== fa || fdata !== fd) $fatal(1,"Flatten pass-through");
        end
        @(negedge clk); rst_n=0; we=0; pwe=0;
        repeat(2) @(negedge clk); rst_n=1;
        for(i=0;i<32;i=i+1) begin @(negedge clk); rb=i/16; ra=i%16; pra=i%24; end
        @(negedge clk);
        $display("PASS Hidden RAM/Pose/Flatten checks=%0d (banks, lanes, sync read, read-first, reset retention)",checks);
        $finish;
    end
    initial begin #50000; $fatal(1,"Memories timeout"); end
endmodule
