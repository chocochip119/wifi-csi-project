`timescale 1ns / 1ps

// X-02a: real control/Loader/Encoder/M00, opt-in FC RAM consumer.
module tb_pose_cnn_core;
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

    reg [7:0] blob[0:422991];
    reg [127:0] golden_conv[0:332];
    reg [95:0] golden_param[0:327];
    reg [7:0] golden_lut[0:1023];
    reg [63:0] golden_fcw[0:2431],input_words[0:1439],pool_words[0:383],first_features[0:383];
    integer pbase[0:4],pcount[0:4],boff[0:4],moff[0:4],soff[0:4];
    integer cycle=0,case_id=-1,selected_case=-1,op_start=0,op_cycles=0;
    integer ar_load1=0,ar_load2=0,ar_input=0,ar_fc=0,aw_count=0;
    integer input_writes=0,fc_pushes=0,pose_beats=0,enc_starts=0,enc_start_cycle=0,enc_cycles=0;
    integer drain_cycles=0,pool_bytes=0,error_target=0;
    bit injected=0,monitor_operation=0;
    integer ram_cycles=0,enc_owner_cycles=0,fc_owner_cycles=0;
    integer enc_param_conflicts=0,enc_lut_conflicts=0,fc_param_conflicts=0,fc_lut_conflicts=0;
    integer start_phase[0:2],last_state=0;
    reg [8:0] observed_enc_param=0;
    reg [9:0] observed_enc_lut=0;
    reg [191:0] first_pose=0;
    integer completed_cases=0,successful_infers=0,complete_encoders=0;
    task automatic check(input bit ok,input string text);
        if(!ok) begin $display("FAIL: X-02a case=%0d cycle=%0d state=%0d %s",case_id,cycle,core.u_ctrl.state_reg,text);$fatal(1,"core integration failure");end
    endtask
    function automatic [31:0] word_at(input integer index);
        word_at={blob[index*4+3],blob[index*4+2],blob[index*4+1],blob[index*4]};
    endfunction
    function automatic [63:0] beat_at(input integer off);
        for(integer b=0;b<8;b=b+1) beat_at[b*8+:8]=blob[off+b];
    endfunction
    task prepare_blob;
        integer fd,n,extra,a,lane;
        begin
            fd=$fopen("D:/2609_final_project/wifi-csi-pose-main/HLS/pl_accel_v6/pl_accel_v6_weights.bin","rb");check(fd!=0,"actual blob open");
            n=$fread(blob,fd);extra=$fgetc(fd);$fclose(fd);check(n==422992 && extra==-1,"actual blob exact size");
            check(word_at(0)==32'h36574c50 && word_at(1)==2 && word_at(4)==32'h3bd997a8,"header contract");
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
            for(integer l=0;l<5;l=l+1) for(integer i=0;i<pcount[l];i=i+1) begin
                golden_param[pbase[l]+i]={word_at(soff[l]+i),word_at(moff[l]+i),word_at(boff[l]+i)};
                core.u_fc.golden_param[pbase[l]+i]=golden_param[pbase[l]+i];
            end
            for(integer i=0;i<1024;i=i+1) begin golden_lut[i]=blob[421968+i];core.u_fc.golden_lut[i]=golden_lut[i];end
            for(integer i=0;i<2432;i=i+1) begin golden_fcw[i]=beat_at(i<2048?400688+i*8:418608+(i-2048)*8);core.u_fc.golden_fcw[i]=golden_fcw[i];end
            core.u_fc.ram_test_enable=1;core.u_fc.ram_golden_ready=1;
            core.u_fc.fc2_delay_cycles=2052;core.u_fc.fc3_delay_cycles=388;
            $display("PASS: X-02a FILE bytes=422992 DDR_words=52874 scale=%08h independent_gold_conv=333 param=328 lut=1024 fcw=2432",word_at(4));
        end
    endtask
    task automatic fill_input(input integer pattern);
        reg [31:0] rng;
        reg [63:0] v;
        integer ix;
        begin
            rng=32'h6e01cafe;
            for(integer a=0;a<1440;a=a+1) begin
                for(integer b=0;b<8;b=b+1) begin
                    ix=a*8+b;
                    if(pattern==0) v[b*8+:8]=8'(ix*37+(ix/256)*11+19);
                    else begin rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);v[b*8+:8]=rng[7:0];end
                end
                input_words[a]=v;memory.memory[(INPUT_BASE>>3)+a]=v;
            end
        end
    endtask
    task common_reset;
        begin
            @(negedge clk);resetn=0;reg_start=0;monitor_operation=0;error_target=0;
            repeat(3) @(negedge clk);resetn=1;
            repeat(2) @(negedge clk);
            check(!status_busy && !status_done && status_error==0 && !cfg_ok,"common reset clears control/config");
        end
    endtask
    task automatic command(input integer cmd,input integer fault);
        begin
            @(negedge clk);
            ar_load1=0;ar_load2=0;ar_input=0;ar_fc=0;aw_count=0;input_writes=0;fc_pushes=0;pose_beats=0;
            enc_starts=0;enc_cycles=0;drain_cycles=0;pool_bytes=0;injected=0;error_target=fault;
            ram_cycles=0;enc_owner_cycles=0;fc_owner_cycles=0;
            enc_param_conflicts=0;enc_lut_conflicts=0;fc_param_conflicts=0;fc_lut_conflicts=0;
            for(integer k=0;k<3;k=k+1) start_phase[k]=0;
            monitor_operation=1;reg_cmd=32'(cmd);reg_start=1;
            @(posedge clk);#2;op_start=cycle;check(status_busy,"START accepted busy rises");
            @(negedge clk);reg_start=0;
            while(status_busy) begin @(negedge clk);check(cycle-op_start<1450000,"command deadline");end
            op_cycles=cycle-op_start;monitor_operation=0;error_target=0;
            if(fault==0) check(status_done && status_error==0,"successful command sticky status");
            else check(!status_done && status_error==(fault==4?5:4) && injected,"injected error sticky status");
            check(!mem_rd_busy && !mem_wr_busy,"both M00 paths completed");
            memory.check_quiescent();check(memory.violation_count==0 && core.u_fc.violations==0,"AXI and FC checker violations zero");
        end
    endtask
    task load_ok;
        begin
            command(1,0);
            check(cfg_ok && output_scale_bits==word_at(4),"real Loader output fanout");
            check(ar_load1==47 && ar_load2==187 && enc_starts==0,"LOAD exactly two address ranges");
            $display("PASS: X-02a W2 LOAD cycles=%0d standalone_loader=9772 overhead=%0d AR=%0d+%0d scale=%08h cfg=1",op_cycles,op_cycles-9772,ar_load1,ar_load2,output_scale_bits);
        end
    endtask
    task automatic infer_ok(input integer compare_mode);
        reg [63:0] got;
        integer differing;
        begin
            for(integer b=-1;b<4;b=b+1) memory.memory.delete((OUTPUT_BASE>>3)+b);
            command(0,0);
            check(input_writes==1440 && fc_pushes==49152 && enc_starts==1 && enc_cycles==1278889,"real input/Encoder/FC1 counts and timing");
            check(ar_input==90 && ar_fc==3073 && aw_count==1 && pose_beats==3,"actual burst split at FC1 base+5936");
            check(start_phase[0]==1 && start_phase[1]==1 && start_phase[2]==1,"one START per FC phase");
            check(core.u_fc.flat_reads==384 && core.u_fc.param_reads[0]==128 && core.u_fc.param_reads[1]==128 && core.u_fc.param_reads[2]==24,"full flat and Param ranges");
            check(core.u_fc.lut_reads[0]==256 && core.u_fc.lut_reads[1]==256 && core.u_fc.fcw_reads[1]==2048 && core.u_fc.fcw_reads[2]==384,"full LUT/FCW ranges");
            check(pool_bytes==3072,"all Pool feature bytes written");
            check(core.u_fc.unowned_param_reads==0 && core.u_fc.unowned_lut_reads==0,"normal FC reads always own shared ports");
            for(integer k=0;k<49152;k=k+1) check(core.u_fc.consumed[k]===beat_at(5936+k*8),"all consumed FC1 weight words");
            for(integer b=0;b<24;b=b+1) begin
                got=memory.mem_word(OUTPUT_BASE+32'((b/8)*8));
                check(got[(b%8)*8+:8]===core.pose_data[b*8+:8],"DDR pose byte matches stub output");
            end
            check(!memory.memory.exists((OUTPUT_BASE>>3)-1) && !memory.memory.exists((OUTPUT_BASE>>3)+3),"write guards unwritten");
            differing=0;
            for(integer a=0;a<384;a=a+1) begin
                check(!$isunknown(pool_words[a]),"valid feature words known");
                if(compare_mode==0) first_features[a]=pool_words[a];
                else if(first_features[a]!==pool_words[a]) differing=differing+1;
            end
            if(compare_mode==0) first_pose=core.pose_data;
            if(compare_mode==1) check(differing==0 && core.pose_data===first_pose,"same input repeated without reset: features and digest identical");
            if(compare_mode==2) check(differing>0 && core.pose_data!==first_pose,"changed input changes real features and test digest");
            check(fc_param_conflicts>0 && fc_lut_conflicts>0,"FC owns shared RAM despite different residual Encoder values");
            if(compare_mode>0) check(enc_param_conflicts>0 && enc_lut_conflicts>0,"next Encoder ignores residual FC addresses");
            successful_infers=successful_infers+1;
            $display("PASS: X-02a W3-W5 INFER cycles=%0d enc_elapsed=%0d input_words=%0d FC1_words=%0d AR_input=%0d AR_FC1=%0d AW=%0d pose_bytes=24 ram_1cycle_checks=%0d",op_cycles,enc_cycles,input_writes,fc_pushes,ar_input,ar_fc,aw_count,ram_cycles*6);
            $display("PASS: X-02a W4 OWNERSHIP enc_cycles=%0d fc_cycles=%0d differing_data_enc_param/lut=%0d/%0d fc_param/lut=%0d/%0d enc_residual_param/lut=%0d/%0d fc_residual_param/lut=%0d/%0d",enc_owner_cycles,fc_owner_cycles,enc_param_conflicts,enc_lut_conflicts,fc_param_conflicts,fc_lut_conflicts,observed_enc_param,observed_enc_lut,core.fc_param_raddr,core.fc_lut_raddr);
            $display("PASS: X-02a W5/W7 mode=%0d flat_words=384 feature_changes=%0d digest_pose=%048h legacy_FC_arithmetic=0",compare_mode,differing,core.pose_data);
        end
    endtask

    always @(negedge clk) begin
        core.u_fc.ram_shared_owned=core.param_sel_fc && core.lut_sel_fc;
        if(resetn && monitor_operation && !injected) begin
            if(mem_rd_start && ((error_target==1 && mem_rd_bytes==5936) || (error_target==2 && mem_rd_bytes==11520) || (error_target==3 && mem_rd_bytes==393216))) begin
                memory.inject_rresp=2;memory.inject_rresp_beat=7;injected=1;
            end
            if(mem_wr_start && error_target==4) begin memory.inject_bresp=2;injected=1;end
        end
    end
    always @(posedge clk) begin : monitor
        reg [127:0] expected_conv;
        reg [95:0] expected_param;
        reg [7:0] expected_lut;
        reg [63:0] expected_fcw;
        bit sample_ram,sel;
        integer pa,la,ca,wa,st;
        cycle=cycle+1;
        sample_ram=resetn && cfg_ok && !core.loader_start;
        sel=core.param_sel_fc;st=int'(core.u_ctrl.state_reg);
        ca=int'(core.conv_raddr);pa=sel?int'(core.fc_param_raddr):int'(core.enc_param_raddr);
        la=core.lut_sel_fc?int'(core.fc_lut_raddr):int'(core.enc_lut_raddr);wa=int'(core.fcw_raddr);
        expected_conv=(!$isunknown(core.conv_raddr) && ca>=0 && ca<333)?golden_conv[ca]:'x;
        expected_param=(!$isunknown(sel?core.fc_param_raddr:core.enc_param_raddr) && pa>=0 && pa<328)?golden_param[pa]:'x;
        expected_lut=(!$isunknown(core.lut_sel_fc?core.fc_lut_raddr:core.enc_lut_raddr) && la>=0 && la<1024)?golden_lut[la]:'x;
        expected_fcw=(!$isunknown(core.fcw_raddr) && wa>=0 && wa<2432)?golden_fcw[wa]:'x;
        if(resetn) begin
            check(core.param_sel_fc===(st>=7 && st<=9) && core.lut_sel_fc===core.param_sel_fc,"D09 selects match FC states");
            check(core.flat_raddr===core.u_encoder.feat_raddr && core.flat_rdata===core.u_encoder.feat_rdata,"Flatten direct wiring every cycle");
            if(monitor_operation) begin
                if(M_AXI_ARVALID && M_AXI_ARREADY) case(st)
                    2: ar_load1=ar_load1+1;3: ar_load2=ar_load2+1;5: ar_input=ar_input+1;7:ar_fc=ar_fc+1;
                    11: begin end
                    default:check(0,"unexpected AR outside read states");
                endcase
                if(M_AXI_AWVALID && M_AXI_AWREADY) begin aw_count=aw_count+1;check(M_AXI_AWADDR==OUTPUT_BASE && M_AXI_AWLEN==2,"pose AW address/length");end
                if(core.in_we) begin
                    check(int'(core.in_waddr)==input_writes && core.in_wdata===input_words[input_writes],"input RAM writes all addresses/data");input_writes=input_writes+1;
                end
                if(core.fifo_we) begin check(core.fifo_wdata===beat_at(5936+fc_pushes*8),"FC1 push word order");fc_pushes=fc_pushes+1;end
                if(mem_wr_ready) pose_beats=pose_beats+1;
                if(core.enc_start) begin enc_starts=enc_starts+1;enc_start_cycle=cycle;end
                if(core.enc_done) begin enc_cycles=cycle-enc_start_cycle;complete_encoders=complete_encoders+1;end
                if(core.fc_start) begin
                    start_phase[core.fc_sel]=start_phase[core.fc_sel]+1;
                    check((core.fc_sel==0 && st==6) || (core.fc_sel==1 && st==7) || (core.fc_sel==2 && st==8),"FC START transition selector");
                    if(core.fc_sel==0) begin observed_enc_param=core.enc_param_raddr;observed_enc_lut=core.enc_lut_raddr;end
                end
                if(st==11) begin
                    drain_cycles=drain_cycles+1;
                    check(core.mem_rd_ready && !core.ld_valid && !core.in_we && !core.fifo_we && !core.enc_start && !core.fc_start,"ERR_DRAIN disables consumers");
                end
                if(st==6 && sample_ram) begin
                    enc_owner_cycles=enc_owner_cycles+1;
                    if(core.u_encoder.acc_valid) check(!$isunknown(core.enc_param_raddr),"valid requant request has known address");
                    if(core.u_encoder.u_enc_gelu.rq_valid_r0) check(!$isunknown(core.enc_lut_raddr),"valid GELU request has known address");
                    if(core.fc_param_raddr!=core.enc_param_raddr && golden_param[core.fc_param_raddr]!==expected_param) enc_param_conflicts=enc_param_conflicts+1;
                    if(core.fc_lut_raddr!=core.enc_lut_raddr && golden_lut[core.fc_lut_raddr]!==expected_lut) enc_lut_conflicts=enc_lut_conflicts+1;
                end
                if(sel && sample_ram) begin
                    fc_owner_cycles=fc_owner_cycles+1;
                    if(core.fc_param_raddr!=core.enc_param_raddr && golden_param[core.enc_param_raddr]!==expected_param) fc_param_conflicts=fc_param_conflicts+1;
                    if(core.fc_lut_raddr!=core.enc_lut_raddr && golden_lut[core.enc_lut_raddr]!==expected_lut) fc_lut_conflicts=fc_lut_conflicts+1;
                end
                // Independent feature oracle watches the Pool memory WRITE bus,
                // never the FC read response. Include final write on enc_done edge.
                if(core.u_encoder.u_pool.v_r4) for(integer b=0;b<8;b=b+1) if(core.u_encoder.u_pool.wr_be[b]) begin
                    pool_words[core.u_encoder.u_pool.wr_addr[11:3]][b*8+:8]=core.u_encoder.u_pool.wr_data64[b*8+:8];
                    core.u_fc.golden_flat[core.u_encoder.u_pool.wr_addr[11:3]][b*8+:8]=core.u_encoder.u_pool.wr_data64[b*8+:8];
                    pool_bytes=pool_bytes+1;
                end
            end
        end
        #1;
        if(sample_ram) begin
            check(core.conv_rdata===expected_conv,"Conv read latency=1 and blob value");
            if(core.enc_param_rdata!==expected_param || core.fc_param_rdata!==expected_param) check(0,$sformatf("Param selected read latency=1 addr=%h sel=%b expected=%h enc=%h fc=%h raw_addr=%h",pa,sel,expected_param,core.enc_param_rdata,core.fc_param_rdata,core.enc_param_raddr));
            check(core.enc_lut_rdata===expected_lut && core.fc_lut_rdata===expected_lut,"LUT selected read latency=1");
            check(core.fcw_rdata===expected_fcw,"FCW read latency=1");
            if(monitor_operation) ram_cycles=ram_cycles+1;
        end
    end
    task automatic run_case(input integer id);
        begin
            case_id=id;common_reset();fill_input(0);
            case(id)
                0:begin load_ok();infer_ok(0);infer_ok(1);fill_input(1);infer_ok(2);end
                1:begin command(1,1);check(!cfg_ok && drain_cycles>0 && enc_starts==0,"LOAD error leaves cfg invalid and drains");end
                2:begin load_ok();command(0,2);check(enc_starts==0 && drain_cycles>0,"input error before Encoder and drains");end
                3:begin load_ok();command(0,3);check(enc_cycles==1278889 && start_phase[0]==1 && start_phase[1]==0 && drain_cycles>0 && core.u_fc.active,"FC read error leaves FC active until reset");
                    check(core.u_fc.unowned_param_reads>0 && core.u_fc.unowned_lut_reads>0,"ERR_DRAIN revokes shared RAM without aborting FC");
                    $display("PASS: X-02a D08/D09 revoked_param_reads=%0d revoked_lut_reads=%0d FC_active=%b addresses_continue=1 selected_data_checker_continues=1",core.u_fc.unowned_param_reads,core.u_fc.unowned_lut_reads,core.u_fc.active);end
                4:begin load_ok();command(0,4);check(enc_cycles==1278889 && pose_beats==3 && drain_cycles==0,"WR error completes B then FINISH, NEVER ERR_DRAIN");end
                5:begin load_ok();infer_ok(0);end
            endcase
            if(id>=1 && id<=4) $display("PASS: X-02a W6 case=%0d error=%0d cfg=%b cycles=%0d ERR_DRAIN_cycles=%0d enc_starts=%0d input_writes=%0d FC1_pushes=%0d write_beats=%0d rd_busy=0 wr_busy=0",id,status_error,cfg_ok,op_cycles,drain_cycles,enc_starts,input_writes,fc_pushes,pose_beats);
            completed_cases=completed_cases+1;
            $display("PASS: X-02a CASE id=%0d completed=%0d AXI_violations=%0d FC_violations=%0d",id,completed_cases,memory.violation_count,core.u_fc.violations);
        end
    endtask
    initial begin #200000000;$fatal(1,"FAIL: X-02a global deadline");end
    initial begin
        if($value$plusargs("CASE=%d",selected_case)) check(selected_case>=0 && selected_case<=5,"CASE range 0..5");
        prepare_blob();
        for(integer c=0;c<=5;c=c+1) if(selected_case<0 || selected_case==c) run_case(c);
        $display("PASS: X-02a ALL cases=%0d selector=%0d successful_INFERs=%0d real_encoder_completions=%0d interface_ports=28 failures=0",completed_cases,selected_case,successful_infers,complete_encoders);
        $finish;
    end
endmodule
