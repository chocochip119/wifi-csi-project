`timescale 1ns/1ps
// Final RTL S_FETCH -> S_MUL -> S_MAC, per-class S_EVAL: 955*11*3+11=31526 cycles
module tb_ridge_axi_v1;
    localparam NW=5253, NX=478, NC=11, NTEST=40;
    reg clk=0; always #5 clk=~clk;
    reg rstn=0;
    reg [15:0] awaddr=0, araddr=0;
    reg awvalid=0, wvalid=0, arvalid=0, bready=0, rready=0;
    reg [31:0] wdata=0;
    reg [3:0] wstrb=4'hf;
    wire awready,wready,arready,bvalid,rvalid;
    wire [1:0] bresp,rresp;
    wire [31:0] rdata;
    ridge_axi_v1 dut(.aclk(clk),.aresetn(rstn),
        .s_axi_awaddr(awaddr),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
        .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
        .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
        .s_axi_araddr(araddr),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
        .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready));
    reg [31:0] weights [0:NW-1];
    reg [63:0] biases [0:NC-1];
    reg [31:0] features [0:NTEST*NX-1];
    reg [63:0] raw_scores [0:NTEST*NC-1];
    reg [31:0] winners [0:NTEST-1];
    integer t,i,j,poll;
    reg [31:0] tmp,lo,hi;
    reg [63:0] actual;

    task axi_write;
        input [15:0] addr;
        input [31:0] value;
        input [3:0] strb;
        input [1:0] exp_resp;
        reg aw_seen,w_seen;
        begin
            @(negedge clk);
            awaddr=addr; awvalid=1; wdata=value; wstrb=strb; wvalid=1;
            aw_seen=0; w_seen=0; bready=0;
            while (!aw_seen || !w_seen) begin
                @(posedge clk);
                if (awvalid && awready) aw_seen=1;
                if (wvalid && wready) w_seen=1;
                @(negedge clk);
                if (aw_seen) awvalid=0;
                if (w_seen) wvalid=0;
            end
            bready=1;
            @(posedge clk);
            while (!bvalid) @(posedge clk);
            if(bresp!==exp_resp) $fatal(1,"AXI write B response at %h was %b wanted %b",addr,bresp,exp_resp);
            @(negedge clk); bready=0;
        end
    endtask
    // Directed independent AW/W tests, with an intentionally stalled B response.
    task axi_write_split;
        input [15:0] addr;
        input [31:0] value;
        input integer aw_first;
        reg seen;
        begin
            @(negedge clk); bready=0;
            if(aw_first!=0)begin awaddr=addr;awvalid=1;end
            else begin wdata=value;wstrb=4'hf;wvalid=1;end
            seen=0;
            while(!seen)begin
                @(posedge clk);
                if(aw_first!=0 && awvalid&&awready)seen=1;
                if(aw_first==0 && wvalid&&wready)seen=1;
                @(negedge clk);
                if(seen)begin if(aw_first!=0)awvalid=0;else wvalid=0;end
            end
            repeat(5)@(posedge clk);
            @(negedge clk);
            if(aw_first!=0)begin wdata=value;wstrb=4'hf;wvalid=1;end
            else begin awaddr=addr;awvalid=1;end
            seen=0;
            while(!seen)begin
                @(posedge clk);
                if(aw_first!=0 && wvalid&&wready)seen=1;
                if(aw_first==0 && awvalid&&awready)seen=1;
                @(negedge clk);
                if(seen)begin if(aw_first!=0)wvalid=0;else awvalid=0;end
            end
            @(posedge clk);while(!bvalid)@(posedge clk);
            if(bresp!==0)$fatal(1,"split write returned SLVERR");
            repeat(4)begin @(posedge clk);if(!bvalid||bresp!==0)$fatal(1,"B response not stable");end
            @(negedge clk);bready=1;
            @(posedge clk);@(negedge clk);bready=0;
        end
    endtask
    task axi_read;
        input [15:0] addr;
        output [31:0] data;
        reg seen;
        begin
            @(negedge clk);
            araddr=addr; arvalid=1; rready=0; seen=0;
            while (!seen) begin
                @(posedge clk);
                if (arvalid && arready) seen=1;
                @(negedge clk);
                if (seen) arvalid=0;
            end
            rready=1;
            @(posedge clk);
            while (!rvalid) @(posedge clk);
            if(rresp!==0) $fatal(1,"AXI read SLVERR %h",addr);
            data=rdata;
            @(negedge clk); rready=0;
        end
    endtask
    // Prevent infinite simulation when a transaction stalls permanently.
    initial begin
        #50000000;
        $fatal(1,"Global TB timeout: AXI or FSM never completed");
    end

    task axi_read_resp;
        input [15:0] addr;
        input [1:0] exp_resp;
        output [31:0] data;
        reg seen;
        begin
            @(negedge clk);
            araddr=addr; arvalid=1; rready=0; seen=0;
            while (!seen) begin
                @(posedge clk);
                if (arvalid && arready) seen=1;
                @(negedge clk);
                if (seen) arvalid=0;
            end
            // An intentionally stalled RREADY exercises stable RDATA/RRESP.
            repeat (3) begin
                @(posedge clk);
                if (!rvalid || rresp!==exp_resp)
                    $fatal(1,"Read response changed while stalled at %h",addr);
            end
            data=rdata;
            @(negedge clk); rready=1;
            @(posedge clk);
            @(negedge clk); rready=0;
        end
    endtask

    initial begin
        $readmemh("generated/weights.mem",weights);
        $readmemh("generated/biases.mem",biases);
        $readmemh("generated/features.mem",features);
        $readmemh("generated/raw_scores.mem",raw_scores);
        $readmemh("generated/winner_code.mem",winners);
        repeat(8) @(posedge clk);
        @(negedge clk);rstn=1;
        axi_read(16'h38,tmp); if(tmp!==32'h52444731) $fatal(1,"bad core id");
        axi_read_resp(16'h28,2'b10,tmp);
        if(tmp!==0) $fatal(1,"RESULT exposed before first DONE");
        axi_read_resp(16'h05,2'b10,tmp);
        if(tmp!==0) $fatal(1,"unaligned STATUS read returned data");
        axi_read_resp(16'h10,2'b10,tmp);
        if(tmp!==0) $fatal(1,"write-only DATA register unexpectedly readable");
        axi_write(16'h11,32'h11223344,4'hf,2'b10);
        axi_read(16'h40,tmp);if(tmp!==0)$fatal(1,"unaligned MODEL_DATA write changed model count");
        axi_write(16'h00,32'h3,4'hf,2'b10);
        axi_read(16'h08,tmp);if(tmp!==4)$fatal(1,"multiple CONTROL commands incorrectly accepted");
        axi_write(16'h00,32'h4,4'hf,2'b00);
        // Negative tests: START before model and incomplete load must fail.
        axi_write(16'h00,32'h1,4'hf,2'b10);
        axi_read(16'h08,tmp);if(tmp!==1)$fatal(1,"missing model error not set");
        axi_write(16'h00,32'h4,4'hf,2'b00);
        axi_write(16'h0c,0,4'hf,2'b00);
        axi_write(16'h10,32'h00010001,4'b0011,2'b10);
        axi_read(16'h40,tmp);if(tmp!==0)$fatal(1,"WSTRB incorrectly incremented pointer");
        axi_write(16'h00,32'h4,4'hf,2'b00);

        // AWVALID and WVALID arrive separately; BVALID must survive backpressure.
        axi_write_split(16'h0c,0,1);
        axi_write_split(16'h14,0,0);
        // Model upload: 5253 packed words; 11 signed int64 biases.
        for(i=0;i<NW;i=i+1) axi_write(16'h10,weights[i],4'hf,2'b00);
        for(i=0;i<NC;i=i+1) begin
            axi_write(16'h18,biases[i][31:0],4'hf,2'b00);
            axi_write(16'h1c,biases[i][63:32],4'hf,2'b00);
        end
        axi_write(16'h00,32'h2,4'hf,2'b00);
        axi_read(16'h04,tmp);if(!tmp[3]) $fatal(1,"model not valid after commit");
        axi_write(16'h00,32'h4,4'hf,2'b00);

        // START with incomplete feature buffer must be rejected.
        axi_write(16'h00,32'h1,4'hf,2'b10);
        axi_read(16'h08,tmp);if(tmp!==2)$fatal(1,"missing features error not set");
        axi_write(16'h00,32'h4,4'hf,2'b00);
        for(t=0;t<NTEST;t=t+1) begin
            axi_write(16'h20,32'd0,4'hf,2'b00);
            for(i=0;i<NX;i=i+1) axi_write(16'h24,features[t*NX+i],4'hf,2'b00);
            axi_write(16'h00,32'h1,4'hf,2'b00);
            if(t==0)begin
                // Reprogramming weights during a running inference is forbidden.
                axi_write(16'h10,32'h12345678,4'hf,2'b10);
                axi_read(16'h08,tmp); if(tmp!==5) $fatal(1,"busy model write error missing");
                axi_write(16'h00,32'h4,4'hf,2'b00);
            end
            poll=0;
            axi_read(16'h04,tmp);
            while(!tmp[1] && poll<15000) begin
                poll=poll+1;
                axi_read(16'h04,tmp);
            end
            if(!tmp[1] || tmp[2])$fatal(1,"no DONE / error in case %0d status=%h",t,tmp);
            axi_read(16'h28,tmp);
            if(tmp[7:4] > 10 || tmp[3:0] > 10) $fatal(1,"bad result idx case=%0d",t);
            if(tmp[7:4]!==winners[t][3:0])
                $fatal(1,"CLASS MISMATCH case=%0d got=%0d expected=%0d",t,tmp[7:4],winners[t]);
            for(j=0;j<NC;j=j+1) begin
                axi_write(16'h2c,j,4'hf,2'b00);
                axi_read(16'h30,lo); axi_read(16'h34,hi);
                actual={hi,lo};
                if(actual!==raw_scores[t*NC+j])
                    $fatal(1,"SCORE mismatch case=%0d class=%0d got=%h exp=%h",t,j,actual,raw_scores[t*NC+j]);
            end
            axi_read(16'h3c,tmp);
            if(tmp!==32'd31526) $fatal(1,"cycle count wrong: %d",tmp);
            $display("PASS case=%0d wire_code=%0d cycles=%0d",t,winners[t],tmp);
        end
        // A partial post-inference model update must revoke both prior result
        // and MODEL_VALID, so an old class cannot be mistaken for new output.
        axi_write(16'h14,0,4'hf,2'b00);
        axi_write(16'h18,biases[0][31:0],4'hf,2'b00);
        axi_read(16'h04,tmp);
        if (tmp[1] || tmp[3]) $fatal(1,"partial model change preserved DONE/MODEL_VALID");
        axi_read_resp(16'h28,2'b10,tmp);
        if (tmp!==0) $fatal(1,"stale result readable during model update");
        axi_write(16'h00,32'h2,4'hf,2'b10);
        axi_read(16'h08,tmp);
        if (tmp!==1) $fatal(1,"partial model commit did not fail");
        // Re-upload and then reset while the MAC is active.
        axi_write(16'h0c,0,4'hf,2'b00);
        axi_write(16'h14,0,4'hf,2'b00);
        for(i=0;i<NW;i=i+1) axi_write(16'h10,weights[i],4'hf,2'b00);
        for(i=0;i<NC;i=i+1) begin
            axi_write(16'h18,biases[i][31:0],4'hf,2'b00);
            axi_write(16'h1c,biases[i][63:32],4'hf,2'b00);
        end
        axi_write(16'h00,32'h2,4'hf,2'b00);
        axi_write(16'h20,0,4'hf,2'b00);
        for(i=0;i<NX;i=i+1) axi_write(16'h24,features[i],4'hf,2'b00);
        axi_write(16'h00,32'h1,4'hf,2'b00);
        axi_read(16'h04,tmp);
        if(!tmp[0]) $fatal(1,"expected BUSY before reset-in-flight test");
        repeat (6) @(posedge clk);
        @(negedge clk); rstn=0;
        repeat(5) @(posedge clk);
        @(negedge clk); rstn=1;
        axi_read(16'h04,tmp);
        if (tmp!==0) $fatal(1,"reset failed to clear accelerator state");
        axi_write(16'h00,32'h1,4'hf,2'b10);
        axi_read(16'h08,tmp);
        if (tmp!==1) $fatal(1,"model incorrectly retained after reset");
        $display("PASS all %0d fixed-point cases, AXI-Lite errors, exact scores, class mapping, model invalidation and reset",NTEST);
        $finish;
    end
endmodule
