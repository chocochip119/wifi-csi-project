`timescale 1ns/1ps
module tb_fc_gelu;
    reg clk=0, rst_n=0, valid=0;
    reg [7:0] q=0;
    reg [8:0] tag=0;
    reg [1:0] table_sel=0;
    wire [9:0] addr;
    reg [7:0] lut[0:1023], data;
    wire [7:0] out;
    wire ov;
    wire [8:0] ot;
    reg ev;
    reg [8:0] et;
    reg [7:0] eq;
    integer t, x, signed_q, count=0;
    always #5 clk=~clk;
    gelu_core dut(clk,rst_n,q,valid,tag,table_sel,addr,data,out,ov,ot);
    always @(posedge clk) data<=lut[addr];
    always @(posedge clk) begin
        signed_q=$signed(q);
        ev=rst_n && valid; et=tag; eq=lut[table_sel*256+signed_q+128];
        if(rst_n && addr !== {table_sel,(q^8'h80)}) $fatal(1,"GELU address");
        #1;
        if(ov !== ev) $fatal(1,"GELU valid latency");
        if(ov) begin
            if({ot,out} !== {et,eq}) $fatal(1,"GELU table/tag/data mismatch");
            count=count+1;
        end
    end
    initial begin
        if ($test$plusargs("waves")) begin $dumpfile("tb_fc_gelu.vcd"); $dumpvars(0,tb_fc_gelu); end
        $readmemh("lut.hex",lut);
        repeat(3) @(negedge clk); rst_n=1;
        for(t=0;t<4;t=t+1) for(x=-128;x<128;x=x+1) begin
            @(negedge clk); valid=1; table_sel=t; q=x; tag=(t*256+x+128)%512;
            if(x%13==0) begin @(negedge clk); valid=0; end
        end
        @(negedge clk); valid=0; repeat(3) @(negedge clk);
        if(count!=1024) $fatal(1,"GELU missing outputs");
        rst_n=0; @(negedge clk);
        $display("PASS GELU all 1024 table/input addresses, signed index, bubbles, latency"); $finish;
    end
    initial begin #20000; $fatal(1,"GELU timeout"); end
endmodule
