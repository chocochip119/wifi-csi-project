`timescale 1ns/1ps
module tb_fc_mac;
    reg clk=0, rst_n=0, valid=0, first=0, last=0;
    reg [63:0] act=0, weight=0;
    reg [8:0] tag=0;
    wire [31:0] acc;
    wire av;
    wire [8:0] at;
    integer seed=201, cycle=0, got=0, scheduled=0, lane, neuron, group_no, groups;
    integer x, w;
    reg signed [31:0] sum=0, dot;
    reg [8:0] first_tag;
    reg ev[0:3];
    reg [31:0] ea[0:3];
    reg [8:0] et[0:3];
    always #5 clk=~clk;
    fc_mac dut(clk,rst_n,act,weight,valid,first,last,tag,acc,av,at);
    always @(posedge clk) begin
        if (!rst_n) begin
            for (integer i=0;i<4;i=i+1) ev[i]=0;
            sum=0;
        end else begin
            for (integer i=3;i>0;i=i-1) begin ev[i]=ev[i-1]; ea[i]=ea[i-1]; et[i]=et[i-1]; end
            ev[0]=0;
            if (valid) begin
                dot=0;
                for (integer i=0;i<8;i=i+1) dot=dot+$signed(act[8*i+:8])*$signed(weight[8*i+:8]);
                if (first) begin sum=dot; first_tag=tag; end
                else sum=sum+dot;
                if (last) begin ev[0]=1; ea[0]=sum; et[0]=first_tag; scheduled=scheduled+1; end
            end
        end
        #1;
        if (av !== ev[3]) $fatal(1,"MAC valid latency cycle=%0d",cycle);
        if (av) begin
            if (acc !== ea[3] || at !== et[3]) $fatal(1,"MAC result got=%0d exp=%0d tag=%h/%h",$signed(acc),$signed(ea[3]),at,et[3]);
            got=got+1;
        end
        cycle=cycle+1;
    end
    task beat(input f,input l,input integer mode);
        begin
            @(negedge clk); valid=1; first=f; last=l; tag=$random(seed);
            for (lane=0;lane<8;lane=lane+1) begin
                case(mode)
                    0: begin x=-128; w=-128; end
                    1: begin x=-128; w=127; end
                    2: begin x=127; w=127; end
                    default: begin x=$random(seed); w=$random(seed); end
                endcase
                act[8*lane+:8]=x; weight[8*lane+:8]=w;
            end
        end
    endtask
    task bubble;
        begin @(negedge clk); valid=0; first=1; last=1; act=64'h8080808080808080; end
    endtask
    initial begin
        if ($test$plusargs("waves")) begin $dumpfile("tb_fc_mac.vcd"); $dumpvars(0,tb_fc_mac); end
        repeat(3) @(negedge clk); rst_n=1;
        beat(1,0,0); beat(0,1,1);
        @(negedge clk); valid=0; rst_n=0;
        repeat(2) @(negedge clk); rst_n=1;
        for (neuron=0;neuron<256;neuron=neuron+1) begin
            groups=(neuron==3)?640:1+(neuron%17);
            for (group_no=0;group_no<groups;group_no=group_no+1) begin
                if (neuron>3 && ($random(seed)&7)==0) bubble;
                beat(group_no==0,group_no==groups-1,(neuron<3)?neuron:3);
            end
        end
        bubble; repeat(8) @(negedge clk);
        if (got!=256) $fatal(1,"MAC missing outputs got=%0d",got);
        $display("PASS MAC outputs=%0d (signed extremes, 640 groups, bubbles, reset flush)",got);
        $finish;
    end
    initial begin #200000; $fatal(1,"MAC timeout"); end
endmodule
