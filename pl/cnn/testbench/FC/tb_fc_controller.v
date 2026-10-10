`timescale 1ns/1ps
module tb_fc_controller;
    reg clk=0, rst_n=0, start=0, store_done=0, empty=1;
    reg [1:0] sel=0;
    reg [63:0] fifo_data=0;
    wire done, re, valid, first, last;
    wire [1:0] active;
    wire [63:0] weight;
    wire [2:0] flat;
    wire [4:0] hidden;
    wire [11:0] waddr;
    wire [8:0] tag;
    integer layer=-1, issued=0, observed=0, cycles=0, completions=0;
    integer g, o, groups, outputs;
    reg pending=0, pf=0, pl=0;
    reg [8:0] pt;
    reg [63:0] pw;
    always #5 clk=~clk;
    fc_controller #(.RX_NUM(3),.WORDS_PER_RX(2),.FC1_OUT_NUM(3),.FC2_OUT_NUM(3),.FC3_OUT_NUM(2))
        dut(clk,rst_n,start,sel,store_done,done,active,empty,fifo_data,re,weight,flat,hidden,waddr,valid,first,last,tag);
    always @(posedge clk) begin
        pending=0;
        if(rst_n && layer>=0) begin
            groups=(layer==0)?6:16; outputs=(layer==2)?2:3;
            if(issued<groups*outputs && active==layer && (!empty || layer!=0) && dut.state==1) begin
                g=issued%groups; o=issued/groups;
                if(re !== (layer==0)) $fatal(1,"Controller fifo_re");
                if(layer==0 && flat !== g) $fatal(1,"Controller flatten address");
                if(layer>0 && (hidden !== ((layer==2?16:0)+g) || waddr !== ((layer==2?2048:0)+o*16+g)))
                    $fatal(1,"Controller hidden/weight address");
                pending=1; pf=g==0; pl=g==groups-1; pt=layer*128+o; pw=fifo_data;
                issued=issued+1;
            end else if(re) $fatal(1,"Controller illegal FIFO pop");
        end
        #1;
        if(valid !== pending) $fatal(1,"Controller issue latency/stall");
        if(valid) begin
            if({first,last,tag} !== {pf,pl,pt}) $fatal(1,"Controller metadata");
            if(layer==0 && weight !== pw) $fatal(1,"Controller FWFT latch");
            observed=observed+1;
        end
        if(done) completions=completions+1;
        cycles=cycles+1;
    end
    initial begin
        if ($test$plusargs("waves")) begin $dumpfile("tb_fc_controller.vcd"); $dumpvars(0,tb_fc_controller); end
        repeat(3) @(negedge clk); rst_n=1;
        start=1; sel=3; repeat(3) @(negedge clk); start=0;
        if(done || valid || re) $fatal(1,"Invalid layer accepted");
        for(layer=0;layer<3;layer=layer+1) begin
            issued=0; observed=0; sel=layer; start=1;
            @(negedge clk); start=0;
            groups=(layer==0)?6:16; outputs=(layer==2)?2:3;
            while(observed<groups*outputs) begin
                @(negedge clk); empty=(cycles%4==0); fifo_data=fifo_data+1;
                // Busy start/selector changes must not alter the accepted layer.
                sel=(layer+1)%3; start=(cycles%7==0);
                if(done) $fatal(1,"Controller early done");
            end
            start=0;
            repeat(12) begin @(negedge clk); if(done || valid || re) $fatal(1,"Controller must wait for store"); end
            store_done=1; @(negedge clk); store_done=0;
            if(!done) $fatal(1,"Controller missing done");
            @(negedge clk); if(done) $fatal(1,"Controller done pulse width");
        end
        layer=-1; rst_n=0; @(negedge clk);
        if(completions!=3) $fatal(1,"Controller completions");
        $display("PASS Controller FC1/2/3 addresses, stalls, busy start, invalid selector, store wait, done pulses"); $finish;
    end
    initial begin #20000; $fatal(1,"Controller timeout"); end
endmodule
