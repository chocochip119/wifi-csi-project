`timescale 1ns/1ps
module tb_fc_top;
    parameter RX=5;
    parameter FIFO_DEPTH=(RX==5)?512:8;
    localparam WORDS=RX*128, AW=$clog2(WORDS), TOTAL_W=WORDS*128;
    reg clk=0, rst_n=0, start=0, we=0;
    reg [1:0] sel=0;
    reg [63:0] wdata=0;
    wire done, full, empty;
    wire [AW-1:0] faddr;
    wire [11:0] waddr;
    wire [8:0] paddr;
    wire [9:0] laddr;
    reg [63:0] fdata, wram_data;
    reg [95:0] pdata;
    reg [7:0] ldata;
    reg [4:0] pose_addr=0;
    wire [7:0] pose_data;
    reg [63:0] features[0:WORDS-1], weights1[0:TOTAL_W-1], weights23[0:4095];
    reg [95:0] params[0:279];
    reg [7:0] lut[0:1023], expected[0:279];
    reg [31:0] expected_acc[0:279];
    reg feeding=0, checking=0;
    integer feed_idx=0, cycle=0, layer=0, iteration, n, idx;
    integer mac_count=0, output_count=0, done_count=0, stalled=0, blocked=0;
    integer layer_begin=0, layer_cycles;
    always #5 clk=~clk;
    fc_top #(.RX_NUM(RX),.FC1_FIFO_DEPTH(FIFO_DEPTH)) dut(
        .clk(clk),.rst_n(rst_n),.fc_start(start),.fc_sel(sel),.fc_done(done),
        .feat_raddr(faddr),.feat_rdata(fdata),.fc1_fifo_we(we),.fc1_fifo_wdata(wdata),
        .fc1_fifo_full(full),.fc1_fifo_empty(empty),.fcw_raddr(waddr),.fcw_rdata(wram_data),
        .fc_param_raddr(paddr),.fc_param_rdata(pdata),.fc_lut_raddr(laddr),.fc_lut_rdata(ldata),
        .pose_raddr(pose_addr),.pose_rdata(pose_data));
    // All three external memories obey the production one-cycle synchronous contract.
    always @(posedge clk) begin
        fdata<=features[faddr]; wram_data<=weights23[waddr]; pdata<=params[paddr]; ldata<=lut[laddr];
        if(rst_n && we && !full) feed_idx=feed_idx+1;
        if(checking && layer==0 && empty && dut.u_fc_controller.state==1) stalled=stalled+1;
        if(checking && full) blocked=blocked+1;
        cycle=cycle+1;
        #1;
        if(checking && rst_n) begin
            if(dut.acc_valid) begin
                idx=(layer==0?0:layer==1?128:256)+mac_count;
                if(mac_count>=(layer==2?24:128) || dut.acc_tag !== layer*128+mac_count || dut.mac_acc !== expected_acc[idx])
                    $fatal(1,"Top RX%0d layer=%0d MAC n=%0d got=%0d expected=%0d tag=%h",RX,layer,mac_count,$signed(dut.mac_acc),$signed(expected_acc[idx]),dut.acc_tag);
                mac_count=mac_count+1;
            end
            if((layer<2 && dut.hidden_we) || (layer==2 && dut.pose_we)) begin
                idx=(layer==0?0:layer==1?128:256)+output_count;
                if(output_count>=(layer==2?24:128)) $fatal(1,"Top extra output");
                if(layer<2) begin
                    if(dut.gelu_tag !== layer*128+output_count || dut.hidden_wbank !== (layer==1) ||
                       dut.hidden_waddr !== output_count || dut.hidden_wdata !== expected[idx])
                        $fatal(1,"Top hidden store layer=%0d n=%0d got=%h expected=%h",layer,output_count,dut.hidden_wdata,expected[idx]);
                end else if(dut.pose_waddr !== output_count || dut.pose_wdata !== expected[idx])
                    $fatal(1,"Top pose store n=%0d got=%h expected=%h",output_count,dut.pose_wdata,expected[idx]);
                output_count=output_count+1;
            end
            if(layer==2 && dut.gelu_in_valid) $fatal(1,"FC3 must bypass GELU");
            if(done) begin
                if(mac_count!=(layer==2?24:128) || output_count!=(layer==2?24:128)) $fatal(1,"Top premature done");
                done_count=done_count+1;
            end
        end
    end
    always @(negedge clk) begin
        if(feeding && rst_n && feed_idx<TOTAL_W) begin
            // Prefill hits full; periodic pauses later force underflow stalls.
            we=(cycle%53<35); wdata=weights1[feed_idx];
        end else we=0;
    end
    task reset_core;
        begin
            @(negedge clk); #2; rst_n=0; start=0; feeding=0; checking=0; we=0;
            repeat(3) @(negedge clk); #2; rst_n=1; feed_idx=0;
        end
    endtask
    task run_layer(input integer selected);
        begin
            @(negedge clk); #2;
            layer=selected; sel=selected; checking=1; mac_count=0; output_count=0;
            if(selected==0) begin
                feed_idx=0; feeding=1;
                while(!full) @(negedge clk);
                #2;
            end
            start=1; layer_begin=cycle;
            @(negedge clk); #2; start=0;
            while(!done) @(negedge clk);
            #2; layer_cycles=cycle-layer_begin;
            if(selected==0 && (feed_idx!=TOTAL_W || !empty)) $fatal(1,"Top FC1 weight consumption");
            feeding=0;
            $display("PASS Top RX=%0d run=%0d FC%0d outputs=%0d cycles=%0d",RX,iteration,selected+1,output_count,layer_cycles);
            @(negedge clk); #2;
            if(done) $fatal(1,"Top done wider than one cycle");
            checking=0;
        end
    endtask
    initial begin
        if ($test$plusargs("waves")) begin $dumpfile("tb_fc_top.vcd"); $dumpvars(0,tb_fc_top); end
        $readmemh("features.hex",features); $readmemh("fc1_weights.hex",weights1);
        $readmemh("fc23_weights.hex",weights23); $readmemh("top_params.hex",params);
        $readmemh("lut.hex",lut); $readmemh("top_acc.hex",expected_acc); $readmemh("top_outputs.hex",expected);
        reset_core;
        @(negedge clk); #2; sel=0; start=1; feeding=1;
        @(negedge clk); #2; start=0;
        repeat(100) @(negedge clk);
        reset_core; // Abort FC1 and flush FIFO/controller/arithmetic pipeline.
        @(negedge clk); #2; sel=3; start=1;
        repeat(3) @(negedge clk); #2; start=0;
        repeat(12) begin @(negedge clk); if(done || dut.acc_valid || dut.hidden_we || dut.pose_we) $fatal(1,"Top stale output/invalid layer"); end
        for(iteration=0;iteration<2;iteration=iteration+1) begin
            run_layer(0); run_layer(1); run_layer(2);
            for(n=0;n<24;n=n+1) begin
                @(negedge clk); #2; pose_addr=n;
                @(posedge clk); #2;
                if(pose_data !== expected[256+n]) $fatal(1,"Top pose read n=%0d",n);
            end
        end
        if(done_count!=6 || !stalled || !blocked) $fatal(1,"Top coverage done=%0d stall=%0d full=%0d",done_count,stalled,blocked);
        $display("PASS Top RX=%0d two inferences without reset, 560 MAC/store comparisons, stall=%0d full=%0d",RX,stalled,blocked);
        $finish;
    end
    initial begin #5000000; $fatal(1,"Top timeout RX=%0d layer=%0d outputs=%0d",RX,layer,output_count); end
endmodule
