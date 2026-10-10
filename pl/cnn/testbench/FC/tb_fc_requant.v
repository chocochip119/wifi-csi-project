`timescale 1ns/1ps
module tb_fc_requant;
    reg clk=0, rst_n=0, valid=0;
    reg [31:0] acc=0;
    reg [8:0] tag=0;
    reg [95:0] params[0:314], data;
    reg [40:0] vectors[0:11999];
    reg [16:0] expected[0:11999];
    wire [7:0] q;
    wire qv;
    wire [8:0] qt;
    reg ev[0:6];
    integer n=0, got=0, seed=301;
    always #5 clk=~clk;
    always @(posedge clk) data<=params[tag];
    requant_core dut(clk,rst_n,acc,valid,tag,data,q,qv,qt);
    always @(posedge clk) begin
        if (!rst_n) begin for(integer i=0;i<7;i=i+1) ev[i]=0; end
        else begin
            for(integer i=6;i>0;i=i-1) ev[i]=ev[i-1];
            ev[0]=valid;
        end
        #1;
        if(qv !== ev[6]) $fatal(1,"Requant valid latency");
        if(qv) begin
            if(got>=12000 || {qt,q} !== expected[got]) $fatal(1,"Requant mismatch n=%0d got=%h expected=%h",got,{qt,q},expected[got]);
            got=got+1;
        end
    end
    initial begin
        if ($test$plusargs("waves")) begin $dumpfile("tb_fc_requant.vcd"); $dumpvars(0,tb_fc_requant); end
        $readmemh("rq_params.hex",params); $readmemh("rq_vectors.hex",vectors); $readmemh("rq_expected.hex",expected);
        repeat(3) @(negedge clk); rst_n=1;
        valid=1; {tag,acc}=vectors[0];
        repeat(3) @(negedge clk);
        rst_n=0; valid=0; repeat(2) @(negedge clk); rst_n=1;
        while(n<12000) begin
            @(negedge clk);
            valid=($random(seed)&7)!=0;
            if(valid) begin {tag,acc}=vectors[n]; n=n+1; end
        end
        @(negedge clk); valid=0;
        repeat(12) @(negedge clk);
        if(got!=12000) $fatal(1,"Requant missing output %0d",got);
        $display("PASS Requant outputs=%0d (independent integer oracle, sync params, reset, shifts INT32_MIN..MAX)",got);
        $finish;
    end
    initial begin #250000; $fatal(1,"Requant timeout"); end
endmodule
