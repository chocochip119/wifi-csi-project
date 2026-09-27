`timescale 1ns / 1ps
module tb_loader_rams;
    reg clk=0;
    always #5 clk=~clk;
    // RAM contracts have no reset input. This is the surrounding control reset.
    reg rst_n=1;
    reg conv_we=0,param_we=0,lut_we=0,fcw_we=0;
    reg [8:0] conv_waddr=0,conv_raddr=0,param_waddr=0,enc_param_raddr=0,fc_param_raddr=0;
    reg [9:0] lut_waddr=0,enc_lut_raddr=0,fc_lut_raddr=0;
    reg [11:0] fcw_waddr=0,fcw_raddr=0;
    reg [127:0] conv_wdata=0;
    reg [95:0] param_wdata=0;
    reg [7:0] lut_wdata=0;
    reg [63:0] fcw_wdata=0;
    reg [15:0] conv_wstrb=0;
    reg [2:0] param_wstrb=0;
    wire [127:0] conv_rdata;
    wire [95:0] enc_param_rdata,fc_param_rdata;
    wire [7:0] enc_lut_rdata,fc_lut_rdata;
    wire [63:0] fcw_rdata;
    reg [127:0] conv_gold[0:332];
    reg [95:0] param_gold[0:327];
    reg [7:0] lut_gold[0:1023];
    reg [63:0] fcw_gold[0:2431];
    integer reads=0;
    conv_weight_ram c(.clk(clk),.conv_we(conv_we),.conv_waddr(conv_waddr),.conv_wdata(conv_wdata),.conv_wstrb(conv_wstrb),.conv_raddr(conv_raddr),.conv_rdata(conv_rdata));
    param_ram p(.clk(clk),.param_we(param_we),.param_waddr(param_waddr),.param_wdata(param_wdata),.param_wstrb(param_wstrb),.enc_param_raddr(enc_param_raddr),.enc_param_rdata(enc_param_rdata),.fc_param_raddr(fc_param_raddr),.fc_param_rdata(fc_param_rdata));
    gelu_lut_ram l(.clk(clk),.lut_we(lut_we),.lut_waddr(lut_waddr),.lut_wdata(lut_wdata),.enc_lut_raddr(enc_lut_raddr),.enc_lut_rdata(enc_lut_rdata),.fc_lut_raddr(fc_lut_raddr),.fc_lut_rdata(fc_lut_rdata));
    fcw_ram f(.clk(clk),.fcw_we(fcw_we),.fcw_waddr(fcw_waddr),.fcw_wdata(fcw_wdata),.fcw_raddr(fcw_raddr),.fcw_rdata(fcw_rdata));
    task automatic check(input bit ok,input string message);
        if(!ok) begin $display("FAIL: RAM %s time=%0t",message,$time);$fatal(1,"RAM mismatch");end
    endtask
    task automatic read_all(input integer ca,input integer pa,input integer la,input integer fa);
        reg [127:0] oldc;
        reg [95:0] oldp;
        reg [7:0] oldl;
        reg [63:0] oldf;
        begin
            @(negedge clk);oldc=conv_rdata;oldp=enc_param_rdata;oldl=enc_lut_rdata;oldf=fcw_rdata;
            conv_raddr=9'(ca);enc_param_raddr=9'(pa);fc_param_raddr=9'(327-pa);
            enc_lut_raddr=10'(la);fc_lut_raddr=10'(1023-la);fcw_raddr=12'(fa);
            #1;
            check(conv_rdata===oldc && enc_param_rdata===oldp && enc_lut_rdata===oldl && fcw_rdata===oldf,"M4 outputs cannot follow address combinationally");
            @(posedge clk);#1;
            check(conv_rdata===conv_gold[ca] && enc_param_rdata===param_gold[pa] && enc_lut_rdata===lut_gold[la] && fcw_rdata===fcw_gold[fa],"M1/M4 data appears after exactly one sampling edge");
            check(enc_param_rdata===fc_param_rdata && enc_lut_rdata===fc_lut_rdata,"M6 one physical read result, encoder selected even with distinct FC address");
            reads=reads+1;
        end
    endtask
    initial begin #1000000;$fatal(1,"FAIL: RAM deadline");end
    initial begin
        for(integer a=0;a<2432;a=a+1) begin
            @(negedge clk);
            conv_we=a<333;param_we=a<328;lut_we=a<1024;fcw_we=1;
            conv_waddr=9'(a%333);param_waddr=9'(a%328);lut_waddr=10'(a%1024);fcw_waddr=12'(a);
            conv_wstrb=16'hffff;param_wstrb=7;
            conv_wdata={32'hfeed0000^32'(a),32'hbeef0000^32'(a*3),32'h13570000^32'(a*5),32'h24680000^32'(a*7)};
            param_wdata={32'h76540000^32'(a),32'h54320000^32'(a*3),32'h32100000^32'(a*7)};
            lut_wdata=8'(a*37+a/256);fcw_wdata={32'habcd0000^32'(a),32'h98760000^32'(a*11)};
            if(conv_we) conv_gold[a]=conv_wdata;
            if(param_we) param_gold[a]=param_wdata;
            if(lut_we) lut_gold[a]=lut_wdata;
            fcw_gold[a]=fcw_wdata;
            @(posedge clk);#1;
        end
        @(negedge clk);conv_we=0;param_we=0;lut_we=0;fcw_we=0;
        for(integer a=0;a<2432;a=a+1) read_all(a%333,a%328,a%1024,a);
        $display("PASS: L-02 RAM M1/M3/M4 full_readback conv=333 param=328 lut=1024 fcw=2432 boundaries=332/327/1023/2431 latency_edges=1");
        for(integer k=0;k<16;k=k+1) begin
            @(negedge clk);conv_we=1;conv_waddr=332;conv_wstrb=16'h1<<k;conv_wdata={16{8'(k+8'ha0)}};
            conv_gold[332][k*8+:8]=8'(k+8'ha0);
            @(posedge clk);#1;@(negedge clk);conv_we=0;
            read_all(332,327,1023,2431);
        end
        for(integer k=0;k<3;k=k+1) begin
            @(negedge clk);param_we=1;param_waddr=327;param_wstrb=3'b1<<k;param_wdata={3{32'h80000000+32'(k)}};
            param_gold[327][k*32+:32]=32'h80000000+32'(k);
            @(posedge clk);#1;@(negedge clk);param_we=0;
            read_all(332,327,1023,2431);
        end
        @(negedge clk);conv_we=1;param_we=1;conv_wstrb=0;param_wstrb=0;conv_wdata=0;param_wdata=0;
        @(posedge clk);#1;@(negedge clk);conv_we=0;param_we=0;
        read_all(332,327,1023,2431);
        $display("PASS: L-02 RAM M2 conv_byte_masks=16 param_field_masks=3 zero_mask=2 untouched_lanes=preserved");
        @(negedge clk);rst_n=0;
        repeat(2) @(posedge clk);
        @(negedge clk);rst_n=1;
        for(integer a=0;a<2432;a=a+1) read_all(a%333,a%328,a%1024,a);
        $display("PASS: L-02 RAM M5 no_reset_ports control_reset_edges=2 full_contents_preserved=333/328/1024/2432");
        $display("PASS: L-02 RAM M1-M6 ALL checks_read_cycles=%0d shared_outputs_equal=1",reads);
        $finish;
    end
endmodule
