`timescale 1ns/1ps
module tb_fc_fifo;
    parameter DEPTH=8;
    reg clk=0, rst_n=0, we=0, re=0;
    reg [63:0] data=0;
    wire full, empty;
    wire [63:0] head;
    reg [63:0] model [0:20000];
    integer rd=0, wr=0, count=0, cycles=0, seed=100;
    integer pushes=0, pops=0, both=0, blocked_write=0, blocked_read=0;
    reg push, pop;
    always #5 clk=~clk;
    fc_fifo #(.DEPTH(DEPTH)) dut(clk,rst_n,we,data,full,re,head,empty);
    always @(posedge clk) begin
        if (!rst_n) begin rd=0; wr=0; count=0; end
        else begin
            if (full !== (count==DEPTH) || empty !== (count==0)) $fatal(1,"FIFO pre flags");
            if (count>0 && head !== model[rd]) $fatal(1,"FIFO FWFT order cycle=%0d",cycles);
            push=we && count<DEPTH; pop=re && count>0;
            if (we && !push) blocked_write=blocked_write+1;
            if (re && !pop) blocked_read=blocked_read+1;
            if (push && pop) both=both+1;
            if (pop) begin rd=rd+1; pops=pops+1; end
            if (push) begin model[wr]=data; wr=wr+1; pushes=pushes+1; end
            count=count+push-pop; cycles=cycles+1;
        end
        #1;
        if (full !== (count==DEPTH) || empty !== (count==0)) $fatal(1,"FIFO post flags");
        if (count>0 && head !== model[rd]) $fatal(1,"FIFO post FWFT");
    end
    task drive(input w,input r);
        begin @(negedge clk); we=w; re=r; data=data+64'h0102030405060709; end
    endtask
    initial begin
        if ($test$plusargs("waves")) begin $dumpfile("tb_fc_fifo.vcd"); $dumpvars(0,tb_fc_fifo); end
        repeat(3) @(negedge clk); rst_n=1;
        drive(0,1); drive(1,1); drive(1,1); drive(0,1);
        repeat(DEPTH+2) drive(1,0);
        drive(1,1); repeat(DEPTH+2) drive(0,1);
        repeat(10000) drive(($random(seed)&3)!=0,($random(seed)&3)!=0);
        drive(1,0); @(negedge clk); rst_n=0;
        repeat(2) @(negedge clk); rst_n=1;
        drive(1,0); drive(0,1); drive(0,0);
        @(negedge clk);
        if (!both || !blocked_write || !blocked_read || !pushes || !pops) $fatal(1,"FIFO coverage missing");
        $display("PASS FIFO cycles=%0d push=%0d pop=%0d simultaneous=%0d",cycles,pushes,pops,both);
        $finish;
    end
    initial begin #200000; $fatal(1,"FIFO timeout"); end
endmodule
