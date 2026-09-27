`timescale 1ns / 1ps

// G-02: file-matched Encoder golden comparison. Existing RTL/stub unchanged.
module tb_golden_encoder;
    reg clk = 0, resetn = 0;
    always #5 clk = ~clk;
    wire mem_rd_start, mem_rd_ready;
    wire [31:0] mem_rd_addr;
    wire [19:0] mem_rd_bytes;
    wire mem_rd_busy, mem_rd_valid, mem_rd_err;
    wire [63:0] mem_rd_data;
    wire mem_wr_start;
    wire [31:0] mem_wr_addr;
    wire [19:0] mem_wr_bytes;
    wire [63:0] mem_wr_data;
    wire mem_wr_busy, mem_wr_ready, mem_wr_err;
    wire M_AXI_AWID;
    wire [31:0] M_AXI_AWADDR;
    wire [7:0] M_AXI_AWLEN;
    wire [2:0] M_AXI_AWSIZE;
    wire [1:0] M_AXI_AWBURST;
    wire M_AXI_AWLOCK;
    wire [3:0] M_AXI_AWCACHE;
    wire [2:0] M_AXI_AWPROT;
    wire [3:0] M_AXI_AWQOS;
    wire M_AXI_AWVALID;
    wire M_AXI_AWREADY;
    wire [63:0] M_AXI_WDATA;
    wire [7:0] M_AXI_WSTRB;
    wire M_AXI_WLAST;
    wire M_AXI_WVALID;
    wire M_AXI_WREADY;
    wire M_AXI_BID;
    wire [1:0] M_AXI_BRESP;
    wire M_AXI_BVALID;
    wire M_AXI_BREADY;
    wire M_AXI_ARID;
    wire [31:0] M_AXI_ARADDR;
    wire [7:0] M_AXI_ARLEN;
    wire [2:0] M_AXI_ARSIZE;
    wire [1:0] M_AXI_ARBURST;
    wire M_AXI_ARLOCK;
    wire [3:0] M_AXI_ARCACHE;
    wire [2:0] M_AXI_ARPROT;
    wire [3:0] M_AXI_ARQOS;
    wire M_AXI_ARVALID;
    wire M_AXI_ARREADY;
    wire M_AXI_RID;
    wire [63:0] M_AXI_RDATA;
    wire [1:0] M_AXI_RRESP;
    wire M_AXI_RLAST;
    wire M_AXI_RVALID;
    wire M_AXI_RREADY;
    pose_cnn_v1_0_M00_AXI m00 (
        .M_AXI_ACLK(clk), .M_AXI_ARESETN(resetn),
        .mem_rd_start(mem_rd_start), .mem_rd_addr(mem_rd_addr), .mem_rd_bytes(mem_rd_bytes),
        .mem_rd_busy(mem_rd_busy), .mem_rd_data(mem_rd_data), .mem_rd_valid(mem_rd_valid),
        .mem_rd_ready(mem_rd_ready), .mem_rd_err(mem_rd_err),
        .mem_wr_start(mem_wr_start),
        .mem_wr_addr(mem_wr_addr),
        .mem_wr_bytes(mem_wr_bytes),
        .mem_wr_data(mem_wr_data),
        .mem_wr_busy(mem_wr_busy), .mem_wr_ready(mem_wr_ready), .mem_wr_err(mem_wr_err),
        .M_AXI_AWID(M_AXI_AWID),
        .M_AXI_AWADDR(M_AXI_AWADDR),
        .M_AXI_AWLEN(M_AXI_AWLEN),
        .M_AXI_AWSIZE(M_AXI_AWSIZE),
        .M_AXI_AWBURST(M_AXI_AWBURST),
        .M_AXI_AWLOCK(M_AXI_AWLOCK),
        .M_AXI_AWCACHE(M_AXI_AWCACHE),
        .M_AXI_AWPROT(M_AXI_AWPROT),
        .M_AXI_AWQOS(M_AXI_AWQOS),
        .M_AXI_AWVALID(M_AXI_AWVALID),
        .M_AXI_AWREADY(M_AXI_AWREADY),
        .M_AXI_WDATA(M_AXI_WDATA),
        .M_AXI_WSTRB(M_AXI_WSTRB),
        .M_AXI_WLAST(M_AXI_WLAST),
        .M_AXI_WVALID(M_AXI_WVALID),
        .M_AXI_WREADY(M_AXI_WREADY),
        .M_AXI_BID(M_AXI_BID),
        .M_AXI_BRESP(M_AXI_BRESP),
        .M_AXI_BVALID(M_AXI_BVALID),
        .M_AXI_BREADY(M_AXI_BREADY),
        .M_AXI_ARID(M_AXI_ARID),
        .M_AXI_ARADDR(M_AXI_ARADDR),
        .M_AXI_ARLEN(M_AXI_ARLEN),
        .M_AXI_ARSIZE(M_AXI_ARSIZE),
        .M_AXI_ARBURST(M_AXI_ARBURST),
        .M_AXI_ARLOCK(M_AXI_ARLOCK),
        .M_AXI_ARCACHE(M_AXI_ARCACHE),
        .M_AXI_ARPROT(M_AXI_ARPROT),
        .M_AXI_ARQOS(M_AXI_ARQOS),
        .M_AXI_ARVALID(M_AXI_ARVALID),
        .M_AXI_ARREADY(M_AXI_ARREADY),
        .M_AXI_RID(M_AXI_RID),
        .M_AXI_RDATA(M_AXI_RDATA),
        .M_AXI_RRESP(M_AXI_RRESP),
        .M_AXI_RLAST(M_AXI_RLAST),
        .M_AXI_RVALID(M_AXI_RVALID),
        .M_AXI_RREADY(M_AXI_RREADY)
    );
    axi4_slave_mem_model memory (
        .clk(clk), .resetn(resetn),
        .M_AXI_AWID(M_AXI_AWID),
        .M_AXI_AWADDR(M_AXI_AWADDR),
        .M_AXI_AWLEN(M_AXI_AWLEN),
        .M_AXI_AWSIZE(M_AXI_AWSIZE),
        .M_AXI_AWBURST(M_AXI_AWBURST),
        .M_AXI_AWLOCK(M_AXI_AWLOCK),
        .M_AXI_AWCACHE(M_AXI_AWCACHE),
        .M_AXI_AWPROT(M_AXI_AWPROT),
        .M_AXI_AWQOS(M_AXI_AWQOS),
        .M_AXI_AWVALID(M_AXI_AWVALID),
        .M_AXI_AWREADY(M_AXI_AWREADY),
        .M_AXI_WDATA(M_AXI_WDATA),
        .M_AXI_WSTRB(M_AXI_WSTRB),
        .M_AXI_WLAST(M_AXI_WLAST),
        .M_AXI_WVALID(M_AXI_WVALID),
        .M_AXI_WREADY(M_AXI_WREADY),
        .M_AXI_BID(M_AXI_BID),
        .M_AXI_BRESP(M_AXI_BRESP),
        .M_AXI_BVALID(M_AXI_BVALID),
        .M_AXI_BREADY(M_AXI_BREADY),
        .M_AXI_ARID(M_AXI_ARID),
        .M_AXI_ARADDR(M_AXI_ARADDR),
        .M_AXI_ARLEN(M_AXI_ARLEN),
        .M_AXI_ARSIZE(M_AXI_ARSIZE),
        .M_AXI_ARBURST(M_AXI_ARBURST),
        .M_AXI_ARLOCK(M_AXI_ARLOCK),
        .M_AXI_ARCACHE(M_AXI_ARCACHE),
        .M_AXI_ARPROT(M_AXI_ARPROT),
        .M_AXI_ARQOS(M_AXI_ARQOS),
        .M_AXI_ARVALID(M_AXI_ARVALID),
        .M_AXI_ARREADY(M_AXI_ARREADY),
        .M_AXI_RID(M_AXI_RID),
        .M_AXI_RDATA(M_AXI_RDATA),
        .M_AXI_RRESP(M_AXI_RRESP),
        .M_AXI_RLAST(M_AXI_RLAST),
        .M_AXI_RVALID(M_AXI_RVALID),
        .M_AXI_RREADY(M_AXI_RREADY)
    );



    localparam [31:0] BASE=32'h10000000,INPUT_BASE=32'h20000000,OUTPUT_BASE=32'h30000000;
    reg reg_start=0,reg_clear_status=0;
    reg [31:0] reg_cmd=0,reg_input_addr=INPUT_BASE,reg_weight_addr=BASE,reg_output_addr=OUTPUT_BASE;
    wire status_busy,status_done,cfg_ok;
    wire [3:0] status_error;
    wire [31:0] output_scale_bits;
    pose_cnn core (
        .clk(clk),
        .rst_n(resetn),
        .reg_start(reg_start),
        .reg_clear_status(reg_clear_status),
        .reg_cmd(reg_cmd),
        .reg_input_addr(reg_input_addr),
        .reg_weight_addr(reg_weight_addr),
        .reg_output_addr(reg_output_addr),
        .status_busy(status_busy),
        .status_done(status_done),
        .status_error(status_error),
        .cfg_ok(cfg_ok),
        .output_scale_bits(output_scale_bits),
        .mem_rd_start(mem_rd_start),
        .mem_rd_addr(mem_rd_addr),
        .mem_rd_bytes(mem_rd_bytes),
        .mem_rd_busy(mem_rd_busy),
        .mem_rd_data(mem_rd_data),
        .mem_rd_valid(mem_rd_valid),
        .mem_rd_ready(mem_rd_ready),
        .mem_rd_err(mem_rd_err),
        .mem_wr_start(mem_wr_start),
        .mem_wr_addr(mem_wr_addr),
        .mem_wr_bytes(mem_wr_bytes),
        .mem_wr_busy(mem_wr_busy),
        .mem_wr_data(mem_wr_data),
        .mem_wr_ready(mem_wr_ready),
        .mem_wr_err(mem_wr_err)
    );


    // Run through the archived G-02 host runner: it checks SHA-256 against both
    // manifests and stages immutable input snapshots in the simulation cwd.
    reg [7:0] blob[0:422991], input_bytes[0:11519];
    reg [63:0] input_words[0:1439],golden_sample[0:383],golden_zero[0:383];
    reg [63:0] captured[0:2][0:383];
    reg [127:0] golden_conv[0:332];
    reg [95:0] golden_param[0:327];
    reg [7:0] golden_lut[0:1023];
    reg [63:0] golden_fcw[0:2431];
    integer pbase[0:4],pcount[0:4],boff[0:4],moff[0:4],soff[0:4];
    integer cycle=0,run_id=-1,operation_start=0,operation_cycles=0;
    integer input_writes=0,enc_starts=0,enc_start_cycle=0,enc_elapsed=0,enc_dones=0;
    integer scan_next=0,scan_count=0,scan_address=0;
    bit scan_active=0,scan_sample=0,tracking=0;
    integer word_mismatch[0:2],byte_mismatch[0:2];
    integer rx_bad[0:2],oc_bad[0:31],oh_bad[0:7];
    integer param_min=512,param_max=-1,lut_min=1024,lut_max=-1;
    integer param_valid_min=512,param_valid_max=-1,lut_valid_min=1024,lut_valid_max=-1;
    integer param_outside=0,lut_outside=0,param_valid_x=0,lut_valid_x=0;
    integer runtime_conv_bad=0,runtime_param_bad=0,runtime_lut_bad=0;
    integer runtime_conv_checks=0,runtime_param_checks=0,runtime_lut_checks=0;
    integer d09_bad=0,pool_param_bad=0,total_word_mismatch=0;
    reg [8:0] diag_conv_addr=0,diag_param_addr=0;
    reg [9:0] diag_lut_addr=0;
    reg [11:0] diag_fcw_addr=0;
    integer diag_conv_bad=0,diag_param_bad=0,diag_lut_bad=0,diag_fcw_bad=0;
    integer results_file;

    task automatic check(input bit ok,input string msg);
        if(!ok) begin $display("FAIL: G-02 control/infrastructure run=%0d cycle=%0d %s",run_id,cycle,msg);$fatal(1,"G-02 could not complete observations");end
    endtask
    function automatic [31:0] word_at(input integer index);
        word_at={blob[index*4+3],blob[index*4+2],blob[index*4+1],blob[index*4]};
    endfunction
    function automatic [63:0] beat_at(input integer off);
        for(integer b=0;b<8;b=b+1) beat_at[b*8+:8]=blob[off+b];
    endfunction
    task prepare_files;
        integer fd,n,extra,a,lane;
        string blob_sha,input_sha,zero_sha;
        begin
            fd=$fopen("h1_verified.txt","r");check(fd!=0,"host SHA preflight record required");
            n=$fscanf(fd,"%s %s %s",blob_sha,input_sha,zero_sha);$fclose(fd);
            check(n==3 && blob_sha=="063d01b880c4d96f1fe61450a72a9911b222ebf67bbbbf560da700a7350b94bb" &&
                input_sha=="949915442c9dfcf980d4880e52b4ff6b08b1b5ff75bdccfa346b807ba0c6fffa","host manifest identity");
            fd=$fopen("blob.bin","rb");check(fd!=0,"blob snapshot open");n=$fread(blob,fd);extra=$fgetc(fd);$fclose(fd);
            check(n==422992 && extra==-1,"blob exact length 422992");
            check(word_at(0)==32'h36574c50 && word_at(1)==2 && word_at(2)==105748,"blob header");
            $readmemh("encoder_sample_u64.hex",golden_sample);$readmemh("encoder_zero_u64.hex",golden_zero);
            for(integer i=0;i<384;i=i+1) check(!$isunknown(golden_sample[i]) && !$isunknown(golden_zero[i]),"all golden words loaded");
            for(integer i=0;i<52874;i=i+1) memory.memory[(BASE>>3)+i]=beat_at(i*8);
            for(integer i=0;i<333;i=i+1) golden_conv[i]=0;
            for(integer i=0;i<720;i=i+1) golden_conv[i%45][(i/45)*8+:8]=blob[32+i];
            for(integer i=0;i<4608;i=i+1) begin
                a=45+((i/144)/16)*144+i%144;lane=(i/144)%16;golden_conv[a][lane*8+:8]=blob[944+i];
            end
            pbase[0]=0;pcount[0]=16;boff[0]=188;moff[0]=204;soff[0]=220;
            pbase[1]=16;pcount[1]=32;boff[1]=1388;moff[1]=1420;soff[1]=1452;
            pbase[2]=48;pcount[2]=128;boff[2]=99788;moff[2]=99916;soff[2]=100044;
            pbase[3]=176;pcount[3]=128;boff[3]=104268;moff[3]=104396;soff[3]=104524;
            pbase[4]=304;pcount[4]=24;boff[4]=105420;moff[4]=105444;soff[4]=105468;
            for(integer l=0;l<5;l=l+1) for(integer i=0;i<pcount[l];i=i+1)
                golden_param[pbase[l]+i]={word_at(soff[l]+i),word_at(moff[l]+i),word_at(boff[l]+i)};
            for(integer i=0;i<1024;i=i+1) golden_lut[i]=blob[421968+i];
            for(integer i=0;i<2432;i=i+1) golden_fcw[i]=beat_at(i<2048?400688+i*8:418608+(i-2048)*8);
            // FC calculation is not the golden oracle. Leave its stock RAM-test
            // mode off and use only its existing flat_raddr output as a scanner.
            core.u_fc.ram_test_enable=0;
            results_file=$fopen("flat_all_words.csv","w");check(results_file!=0,"CSV open");
            $fdisplay(results_file,"run,word,rx,oc,oh_even,golden,actual,byte_mismatch_mask");
            $display("PASS: G-02 H1 blob_bytes=422992 input_bytes=11520 golden_words=384 host_blob_SHA=%s host_input_SHA=%s zero_SHA=%s",blob_sha,input_sha,zero_sha);
        end
    endtask
    task automatic fill_input(input bit zero_case);
        integer fd,n,extra;
        begin
            fd=$fopen(zero_case?"zero_input.bin":"sample_input.bin","rb");check(fd!=0,"golden input snapshot open");
            n=$fread(input_bytes,fd);extra=$fgetc(fd);$fclose(fd);check(n==11520 && extra==-1,"input exact 11520 bytes");
            for(integer a=0;a<1440;a=a+1) begin
                for(integer b=0;b<8;b=b+1) input_words[a][8*b+:8]=input_bytes[8*a+b];
                memory.memory[(INPUT_BASE>>3)+a]=input_words[a];
            end
        end
    endtask
    task automatic command(input integer cmd);
        begin
            @(negedge clk);reg_cmd=32'(cmd);reg_start=1;
            input_writes=0;enc_starts=0;enc_dones=0;enc_elapsed=0;scan_next=0;scan_count=0;
            scan_active=0;scan_sample=0;tracking=cmd==0;
            param_min=512;param_max=-1;lut_min=1024;lut_max=-1;
            param_valid_min=512;param_valid_max=-1;lut_valid_min=1024;lut_valid_max=-1;
            param_outside=0;lut_outside=0;param_valid_x=0;lut_valid_x=0;
            runtime_conv_bad=0;runtime_param_bad=0;runtime_lut_bad=0;d09_bad=0;pool_param_bad=0;
            runtime_conv_checks=0;runtime_param_checks=0;runtime_lut_checks=0;
            @(posedge clk);#2;operation_start=cycle;check(status_busy,"START accepted");
            @(negedge clk);reg_start=0;
            while(status_busy) begin @(negedge clk);check(cycle-operation_start<1450000,"command deadline");end
            operation_cycles=cycle-operation_start;tracking=0;
            check(status_done && status_error==0,"normal command completion");
            check(!mem_rd_busy && !mem_wr_busy,"AXI requests finished");
            memory.check_quiescent();check(memory.violation_count==0 && core.u_fc.violations==0,"AXI/FC protocol zero");
        end
    endtask
    // Address stimulus only. No RAM contents, arithmetic, state or result is forced.
    always @(negedge clk) begin
        scan_sample=0;
        if(resetn && scan_active && scan_next<384) begin
            scan_address=scan_next;core.u_fc.flat_raddr=9'(scan_next);
            scan_next=scan_next+1;scan_sample=1;
        end else if(scan_next==384) scan_active=0;
    end
    always @(posedge clk) begin : observe
        bit enc_sample,conv_known,param_known,lut_known,flat_sample;
        reg [127:0] conv_expected;
        reg [95:0] param_expected;
        reg [7:0] lut_expected;
        integer pa,la;
        cycle=cycle+1;
        enc_sample=resetn && tracking && core.u_ctrl.state_reg==4'd6;
        conv_known=!$isunknown(core.conv_raddr) && core.conv_raddr<333;
        param_known=!$isunknown(core.enc_param_raddr) && core.enc_param_raddr<328;
        lut_known=!$isunknown(core.enc_lut_raddr);
        conv_expected=conv_known?golden_conv[core.conv_raddr]:'x;
        param_expected=param_known?golden_param[core.enc_param_raddr]:'x;
        lut_expected=lut_known?golden_lut[core.enc_lut_raddr]:'x;
        flat_sample=resetn && scan_sample;
        if(resetn && tracking) begin
            if(core.in_we) begin
                check(input_writes<1440 && int'(core.in_waddr)==input_writes && core.in_wdata===input_words[input_writes],"input RAM writes full sequence/data");
                input_writes=input_writes+1;
            end
            if(core.enc_start) begin enc_starts=enc_starts+1;enc_start_cycle=cycle;end
            if(core.enc_done) begin enc_dones=enc_dones+1;enc_elapsed=cycle-enc_start_cycle;scan_active=1;end
        end
        if(enc_sample) begin
            if(core.param_sel_fc!==1'b0 || core.lut_sel_fc!==1'b0) d09_bad=d09_bad+1;
            if(core.u_encoder.pool_mult!==word_at(5) || core.u_encoder.pool_shift!==word_at(6)) pool_param_bad=pool_param_bad+1;
            if(!$isunknown(core.enc_param_raddr)) begin
                pa=int'(core.enc_param_raddr);if(pa<param_min)param_min=pa;if(pa>param_max)param_max=pa;
                if(pa>47)param_outside=param_outside+1;
            end
            if(lut_known) begin
                la=int'(core.enc_lut_raddr);if(la<lut_min)lut_min=la;if(la>lut_max)lut_max=la;
                if(la>511)lut_outside=lut_outside+1;
            end
            if(core.u_encoder.acc_valid) begin
                if($isunknown(core.enc_param_raddr))param_valid_x=param_valid_x+1;
                else begin pa=int'(core.enc_param_raddr);if(pa<param_valid_min)param_valid_min=pa;if(pa>param_valid_max)param_valid_max=pa;end
            end
            if(core.u_encoder.u_enc_gelu.rq_valid_r0) begin
                if(!lut_known)lut_valid_x=lut_valid_x+1;
                else begin la=int'(core.enc_lut_raddr);if(la<lut_valid_min)lut_valid_min=la;if(la>lut_valid_max)lut_valid_max=la;end
            end
        end
        #1;
        if(enc_sample) begin
            if(conv_known) begin runtime_conv_checks=runtime_conv_checks+1;if(core.conv_rdata!==conv_expected)runtime_conv_bad=runtime_conv_bad+1;end
            if(param_known) begin runtime_param_checks=runtime_param_checks+1;if(core.enc_param_rdata!==param_expected)runtime_param_bad=runtime_param_bad+1;end
            if(lut_known) begin runtime_lut_checks=runtime_lut_checks+1;if(core.enc_lut_rdata!==lut_expected)runtime_lut_bad=runtime_lut_bad+1;end
        end
        if(flat_sample) begin
            check(int'(core.flat_raddr)==scan_address,"scanner address stable through RAM read");
            captured[run_id][scan_address]=core.flat_rdata;scan_count=scan_count+1;
        end
    end
    task automatic compare_flat(input integer id);
        integer fd,rx,oc,oh,bad,first;
        reg [63:0] expected,actual;
        reg [7:0] mask;
        begin
            word_mismatch[id]=0;byte_mismatch[id]=0;first=0;
            for(integer i=0;i<3;i=i+1)rx_bad[i]=0;
            for(integer i=0;i<32;i=i+1)oc_bad[i]=0;
            for(integer i=0;i<8;i=i+1)oh_bad[i]=0;
            fd=$fopen($sformatf("rtl_flat_run%0d.hex",id),"w");check(fd!=0,"RTL dump open");
            for(integer a=0;a<384;a=a+1) begin
                expected=id==2?golden_zero[a]:golden_sample[a];actual=captured[id][a];mask=0;
                rx=a/128;oc=(a%128)/4;oh=(a%4)*2;
                for(integer b=0;b<8;b=b+1) if(actual[b*8+:8]!==expected[b*8+:8]) begin
                    mask[b]=1;byte_mismatch[id]=byte_mismatch[id]+1;
                    rx_bad[rx]=rx_bad[rx]+1;oc_bad[oc]=oc_bad[oc]+1;oh_bad[oh+b/4]=oh_bad[oh+b/4]+1;
                end
                if(mask!=0) begin
                    word_mismatch[id]=word_mismatch[id]+1;
                    if(first<5)begin $display("MISMATCH: G-02 H4 run=%0d word=%0d rx=%0d oc=%0d oh_pair=%0d/%0d golden=%016h actual=%016h byte_mask=%02h",id,a,rx,oc,oh,oh+1,expected,actual,mask);first=first+1;end
                end
                $fdisplay(fd,"%016h",actual);
                $fdisplay(results_file,"%0d,%0d,%0d,%0d,%0d,%016h,%016h,%02h",id,a,rx,oc,oh,expected,actual,mask);
            end
            $fclose(fd);total_word_mismatch=total_word_mismatch+word_mismatch[id];
            $display("RESULT: G-02 H4 run=%0d words_equal=%0d words_mismatch=%0d bytes_equal=%0d bytes_mismatch=%0d",id,384-word_mismatch[id],word_mismatch[id],3072-byte_mismatch[id],byte_mismatch[id]);
            if(word_mismatch[id]>0) begin
                for(integer i=0;i<3;i=i+1)$display("OBS: H4 run=%0d rx=%0d mismatched_bytes=%0d",id,i,rx_bad[i]);
                for(integer i=0;i<32;i=i+1)$display("OBS: H4 run=%0d oc=%0d mismatched_bytes=%0d",id,i,oc_bad[i]);
                for(integer i=0;i<8;i=i+1)$display("OBS: H4 run=%0d oh=%0d mismatched_bytes=%0d",id,i,oh_bad[i]);
            end
        end
    endtask
    task diagnose_ram_ports;
        integer fd;
        begin
            check(!status_busy && !core.u_fc.active,"diagnostics only after all execution ends");
            fd=$fopen("ram_diagnostics.csv","w");check(fd!=0,"RAM diagnostic output open");
            $fdisplay(fd,"ram,address,expected,actual");
            // Read via external synchronous ports, never inspect storage arrays.
            // Only idle read addresses are temporarily driven; no write/state force.
            force core.u_loader.conv_raddr=diag_conv_addr;
            force core.u_loader.enc_param_raddr=diag_param_addr;
            force core.u_loader.enc_lut_raddr=diag_lut_addr;
            force core.u_loader.fcw_raddr=diag_fcw_addr;
            for(integer a=0;a<2432;a=a+1) begin
                @(negedge clk);diag_conv_addr=9'(a<333?a:0);diag_param_addr=9'(a<328?a:0);
                diag_lut_addr=10'(a<1024?a:0);diag_fcw_addr=12'(a);
                @(posedge clk);#2;
                if(a<333) begin
                    for(integer b=0;b<16;b=b+1)if(core.conv_rdata[b*8+:8]!==golden_conv[a][b*8+:8])diag_conv_bad=diag_conv_bad+1;
                    $fdisplay(fd,"conv,%0d,%032h,%032h",a,golden_conv[a],core.conv_rdata);
                end
                if(a<328) begin
                    for(integer b=0;b<3;b=b+1)if(core.enc_param_rdata[b*32+:32]!==golden_param[a][b*32+:32])diag_param_bad=diag_param_bad+1;
                    $fdisplay(fd,"param,%0d,%024h,%024h",a,golden_param[a],core.enc_param_rdata);
                end
                if(a<1024) begin
                    if(core.enc_lut_rdata!==golden_lut[a])diag_lut_bad=diag_lut_bad+1;
                    $fdisplay(fd,"lut,%0d,%02h,%02h",a,golden_lut[a],core.enc_lut_rdata);
                end
                if(core.fcw_rdata!==golden_fcw[a])diag_fcw_bad=diag_fcw_bad+1;
                $fdisplay(fd,"fcw,%0d,%016h,%016h",a,golden_fcw[a],core.fcw_rdata);
            end
            @(negedge clk);release core.u_loader.conv_raddr;release core.u_loader.enc_param_raddr;
            release core.u_loader.enc_lut_raddr;release core.u_loader.fcw_raddr;$fclose(fd);
            $display("RESULT: G-02 H5 port_sweep conv_bytes=5328 bad=%0d param_fields=984 bad=%0d LUT_bytes=1024 bad=%0d FCW_words=2432 bad=%0d",diag_conv_bad,diag_param_bad,diag_lut_bad,diag_fcw_bad);
            $display("OBS: G-02 H5 pool_mult=%08h pool_shift=%0d expected_mult=%08h expected_shift=%0d",core.u_encoder.pool_mult,$signed(core.u_encoder.pool_shift),word_at(5),$signed(word_at(6)));
        end
    endtask
    initial begin #70000000;$fatal(1,"FAIL: G-02 global deadline");end
    initial begin : run_all
        integer same_words,changed_words,golden_changed_words,changed_bytes,golden_changed_bytes;
        same_words=0;changed_words=0;golden_changed_words=0;changed_bytes=0;golden_changed_bytes=0;
        prepare_files();
        @(negedge clk);resetn=0;repeat(3)@(negedge clk);resetn=1;repeat(2)@(negedge clk);
        command(1);check(cfg_ok && output_scale_bits==32'h3bd997a8,"LOAD header outputs");
        $display("PASS: G-02 H2 LOAD cycles=%0d X02a=10114 delta=%0d cfg=1 error=0 scale=%08h",operation_cycles,operation_cycles-10114,output_scale_bits);
        for(integer id=0;id<3;id=id+1) begin
            run_id=id;fill_input(id==2);command(0);
            check(input_writes==1440 && enc_starts==1 && enc_dones==1 && scan_count==384,"H3 input/start/done/scan counts");
            $display("PASS: G-02 H3 run=%0d input_words=%0d starts=%0d dones=%0d enc_elapsed=%0d X02a=1278889 delta=%0d infer_cycles=%0d flat_reads=%0d",id,input_writes,enc_starts,enc_dones,enc_elapsed,enc_elapsed-1278889,operation_cycles,scan_count);
            compare_flat(id);
            $display("OBS: G-02 H5 run=%0d raw_param_range=%0d..%0d valid_param_range=%0d..%0d raw_lut_range=%0d..%0d valid_lut_range=%0d..%0d param_outside=%0d lut_outside=%0d valid_X_param/lut=%0d/%0d D09_bad=%0d pool_param_bad=%0d",id,param_min,param_max,param_valid_min,param_valid_max,lut_min,lut_max,lut_valid_min,lut_valid_max,param_outside,lut_outside,param_valid_x,lut_valid_x,d09_bad,pool_param_bad);
            $display("OBS: G-02 H5 run=%0d runtime_conv/param/lut_checks=%0d/%0d/%0d bad=%0d/%0d/%0d",id,runtime_conv_checks,runtime_param_checks,runtime_lut_checks,runtime_conv_bad,runtime_param_bad,runtime_lut_bad);
        end
        for(integer a=0;a<384;a=a+1) begin
            if(captured[0][a]!==captured[1][a])same_words=same_words+1;
            if(captured[0][a]!==captured[2][a])changed_words=changed_words+1;
            if(golden_sample[a]!==golden_zero[a])golden_changed_words=golden_changed_words+1;
            for(integer b=0;b<8;b=b+1) begin
                if(captured[0][a][8*b+:8]!==captured[2][a][8*b+:8])changed_bytes=changed_bytes+1;
                if(golden_sample[a][8*b+:8]!==golden_zero[a][8*b+:8])golden_changed_bytes=golden_changed_bytes+1;
            end
        end
        $display("RESULT: G-02 H6 repeated_input_different_words=%0d changed_input_RTL_words=%0d bytes=%0d golden_words=%0d bytes=%0d",same_words,changed_words,changed_bytes,golden_changed_words,golden_changed_bytes);
        check(same_words==0 && changed_words>0 && golden_changed_words>0,"H6 reproducibility/nonvacuous response");
        if(total_word_mismatch>0)diagnose_ram_ports();else $display("PASS: G-02 H5 full diagnostics skipped: all three comparisons matched");
        $fclose(results_file);memory.check_quiescent();
        $display("RESULT: G-02 COMPLETE cases=3 total_word_mismatches=%0d H4_pass=%0d H6_pass=1 AXI_violations=%0d FC_violations=%0d",total_word_mismatch,total_word_mismatch==0,memory.violation_count,core.u_fc.violations);
        $finish;
    end
endmodule
