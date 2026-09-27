`timescale 1ns / 1ps

// T-05 Top/real-M00 integration fixture. Existing memory RTL/model unchanged.
module tb_top_fc1;
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
    pose_cnn_v1_0_M00_AXI dut (
        .M_AXI_ACLK(clk), .M_AXI_ARESETN(resetn),
        .mem_rd_start(mem_rd_start), .mem_rd_addr(mem_rd_addr), .mem_rd_bytes(mem_rd_bytes),
        .mem_rd_busy(mem_rd_busy), .mem_rd_data(mem_rd_data), .mem_rd_valid(mem_rd_valid),
        .mem_rd_ready(mem_rd_ready), .mem_rd_err(mem_rd_err),
        .mem_wr_start(mem_wr_start), .mem_wr_addr(mem_wr_addr), .mem_wr_bytes(mem_wr_bytes), .mem_wr_data(mem_wr_data),
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


    reg  reg_start = 0;
    reg  reg_clear_status = 0;
    reg [31:0] reg_cmd = 0;
    reg [31:0] reg_input_addr = 0;
    reg [31:0] reg_weight_addr = 0;
    reg [31:0] reg_output_addr = 0;
    wire  status_busy;
    wire  status_done;
    wire [3:0] status_error;
    reg  cfg_ok = 0;
    wire  loader_start;
    wire  loader_done;
    wire  loader_err;
    wire [63:0] ld_data;
    wire  ld_valid;
    wire  ld_ready;
    wire  enc_start;
    wire  enc_done;
    wire  in_we;
    wire [10:0] in_waddr;
    wire [63:0] in_wdata;
    wire  fc_start;
    wire  fc_done;
    wire [1:0] fc_sel;
    wire  fifo_we;
    wire [63:0] fifo_wdata;
    wire  fifo_full;
    wire [191:0] pose_data;

    wire param_sel_fc, lut_sel_fc;
    pose_cnn_ctrl ctrl (
        .param_sel_fc(param_sel_fc), .lut_sel_fc(lut_sel_fc),
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
        .mem_wr_err(mem_wr_err),
        .loader_start(loader_start),
        .loader_done(loader_done),
        .loader_err(loader_err),
        .ld_data(ld_data),
        .ld_valid(ld_valid),
        .ld_ready(ld_ready),
        .enc_start(enc_start),
        .enc_done(enc_done),
        .in_we(in_we),
        .in_waddr(in_waddr),
        .in_wdata(in_wdata),
        .fc_start(fc_start),
        .fc_done(fc_done),
        .fc_sel(fc_sel),
        .fifo_we(fifo_we),
        .fifo_wdata(fifo_wdata),
        .fifo_full(fifo_full),
        .pose_data(pose_data)
    );

    loader_stub loader(.clk(clk),.resetn(resetn),.loader_start(loader_start),
        .ld_data(ld_data),.ld_valid(ld_valid),.ld_ready(ld_ready),.loader_done(loader_done),.loader_err(loader_err));
    in_ram_stub input_ram(.clk(clk),.resetn(resetn),.in_we(in_we),.in_waddr(in_waddr),.in_wdata(in_wdata));
    enc_stub encoder(.clk(clk),.resetn(resetn),.enc_start(enc_start),.enc_done(enc_done));
    // Change only the stub's live selector after sampling. No force on the DUT.
    wire [1:0] tested_fc_sel=fc_start ? fc_sel : (fc_sel ^ 2'b11);
    // Forced early/same done violates the real completion contract. Isolate
    // those two probes at the FC1 boundary; never force the DUT or abort FC.
    bit boundary_probe=0;
    wire model_fc_start=fc_start && (!boundary_probe || fc_sel==0);
    fc_stub fc(.clk(clk),.resetn(resetn),.fc_start(model_fc_start),.fc_sel(tested_fc_sel),
        .fifo_we(fifo_we),.fifo_wdata(fifo_wdata),.fifo_full(fifo_full),.fc_done(fc_done),.pose_data(pose_data),
        .fc_param_raddr(),.fc_param_rdata(96'd0),.fc_lut_raddr(),.fc_lut_rdata(8'd0),
        .fcw_raddr(),.fcw_rdata(64'd0),.flat_raddr(),.flat_rdata(64'd0));
    localparam integer LAST_CASE=10;
    localparam [31:0] INPUT_BASE=32'h1d000000, INPUT_SEED=32'h24681357;
    localparam [31:0] LOAD1_SEED=32'haaaa0001, LOAD2_SEED=32'hcccc0003;
    reg [31:0] base_a, base_b, loaded_base, expected_base, weight_seed, next_ar;
    integer selected=-1, case_id, leg, cycle=0, phase=0, cases_done=0, infer_runs=0;
    integer start_edge, finish_edge, commands, ar1, ar2, raw1, raw2, pushes, input_writes;
    integer load_starts, enc_starts, fc_starts, fc_cycles, fc_busy_cycles, full_samples, full_stalls;
    integer fc_begin, fc_read_end, done_edge, error_at_push, drain_cycles, ar_left, burst_words;
    integer expected_ar1, expected_ar2, full_run, max_full_run, simultaneous_pop_push;
    integer events, inject_before, done_before, repeats_full=-1, repeats_cycles=-1;
    bit active=0, prior_mem_start=0, prior_fc_start=0, prior_busy=0, fault=0, injected=0;
    reg [3:0] prior_state;
    string case_name, done_relation;


    // BASELINE_T06 is only for replay against the saved pre-T07 controller.
    // Default execution always requires the real ERR_DRAIN state.
    bit legacy_drain=0;
    integer drain_entries=0, drain_residence=0, drain_discarded=0, read_fall=0;
    integer drain_from=-1, both_busy_cycles=0, write_only_cycles=0;
    reg [3:0] drain_prior_state=0;
    initial legacy_drain=$test$plusargs("BASELINE_T06");
    task reset_drain_observation;
        begin
            drain_entries=0;drain_residence=0;drain_discarded=0;read_fall=0;
            drain_from=-1;both_busy_cycles=0;write_only_cycles=0;drain_prior_state=0;
        end
    endtask
    task observe_drain;
        begin
            if(ctrl.mem_rd_busy_prev_reg && !mem_rd_busy) read_fall=cycle;
            if(mem_rd_err && (ctrl.state_reg==2 || ctrl.state_reg==3 || ctrl.state_reg==5 || ctrl.state_reg==7)) begin
                check(!ld_valid && !in_we && !fifo_we && mem_rd_ready,
                    "R1 immediate error-cycle consumer gating and RREADY=1");
                check(ctrl.run_error_next==4,"R1 latch MEM_RD_ERR before drain entry");
                if(!legacy_drain) check(ctrl.state_next==11,"R1 each read origin selects ERR_DRAIN=1011");
                drain_from=ctrl.state_reg;
            end
            if(mem_rd_err && mem_rd_valid && mem_rd_ready) drain_discarded=drain_discarded+1;
            if(ctrl.state_reg==11) begin
                if(drain_prior_state!=11) drain_entries=drain_entries+1;
                drain_residence=drain_residence+1;
                check(status_busy && !status_done && status_error==0 && ctrl.run_error_reg==4 &&
                    ctrl.run_error_next==4,"R2 internal error retained; STATUS waits for FINISH");
                check(mem_rd_ready && {ld_valid,in_we,fifo_we,ld_data,in_wdata,fifo_wdata,
                    mem_rd_start,mem_wr_start,loader_start,enc_start,fc_start}==='0,
                    "R2 drain accepts/discards; every consumer and START/data output is zero");
                check(ctrl.state_next==((!mem_rd_busy&&!mem_wr_busy)?12:11),
                    "R3 FINISH requires BOTH engines idle");
                if(mem_rd_busy && mem_wr_busy) both_busy_cycles=both_busy_cycles+1;
                if(!mem_rd_busy && mem_wr_busy) write_only_cycles=write_only_cycles+1;
            end
            drain_prior_state=ctrl.state_reg;
        end
    endtask

    function automatic [63:0] pattern(input reg [31:0] addr,seed);
        pattern={seed^32'hA5C39E71,addr^seed};
    endfunction
    function automatic integer burst_count(input reg [31:0] addr,input integer bytes);
        integer left,n,k;reg [31:0] a;
        begin
            left=bytes/8;a=addr;n=0;
            while(left>0) begin
                k=left<16 ? left:16;
                if(k>(4096-a%4096)/8) k=(4096-a%4096)/8;
                left=left-k;a=a+8*k;n=n+1;
            end
            burst_count=n;
        end
    endfunction
    task automatic check(input bit ok,input string message);
        if(!ok) begin
            $display("FAIL: T-05 %s case=%0d leg=%0d phase=%0d cycle=%0d state=%0d %s",
                case_name,case_id,leg,phase,cycle,ctrl.state_reg,message);
            $fatal(1,"T-05 FC1 mismatch");
        end
    endtask
    task automatic fill_blob(input reg [31:0] base,input reg [31:0] seed_value);
        begin
            memory.mem_fill(base,5936,LOAD1_SEED);
            memory.mem_fill(base+5936,393216,seed_value);
            memory.mem_fill(base+399152,23840,LOAD2_SEED);
        end
    endtask
    always @(negedge clk) begin
        // Mid-stream error after FIFO backpressure has already been exercised.
        if(active && phase==2 && commands==2 && fault && !injected && ar2==80) begin
            memory.inject_rresp=2'b10;memory.inject_rresp_beat=4;injected=1;
        end
    end
    always @(posedge clk) begin
        cycle=cycle+1;
        if(resetn && active) begin
            observe_drain;
            if(reg_start && ctrl.state_reg==0) start_edge=cycle;
            check(!(prior_mem_start && mem_rd_start),"read START one-cycle");
            check(!(prior_fc_start && fc_start),"FC START one-cycle");
            prior_mem_start=mem_rd_start;prior_fc_start=fc_start;
            if(ctrl.state_reg!=9 && ctrl.state_reg!=10)
                check({mem_wr_start,mem_wr_addr,mem_wr_bytes,mem_wr_data}==='0,"write outputs zero through FC1 boundary");
            if(loader_start) load_starts=load_starts+1;
            if(enc_start) enc_starts=enc_starts+1;
            if(mem_rd_start) begin
                check(!mem_rd_busy && commands<2,"exactly two nonoverlapping read commands");
                if(phase==1) begin
                    check(mem_rd_addr==expected_base+(commands==0?0:399152) &&
                          mem_rd_bytes==(commands==0?5936:23840),"LOAD addresses/lengths");
                    if(commands==0) check(loader_start && ctrl.state_reg==1,"LOAD starts on DECODE exit");
                end else begin
                    if(commands==0) check(mem_rd_addr==INPUT_BASE && mem_rd_bytes==11520 && !fc_start,
                        "INFER input command");
                    else begin
                        check(fc_start && fc_sel==0 && ctrl.state_reg==6,"same-edge FC1/read START with select 0");
                        check(mem_rd_addr==loaded_base+5936 && mem_rd_bytes==393216,
                            "D06 FC1 uses loaded base plus 5936, not current weight snapshot");
                        check(ctrl.weight_addr_reg!=loaded_base,"D06 addresses actually differ");
                        fc_begin=cycle;
                    end
                end
                next_ar=mem_rd_addr;ar_left=mem_rd_bytes;commands=commands+1;
            end
            if(M_AXI_ARVALID && M_AXI_ARREADY) begin
                burst_words=ar_left/8;
                if(burst_words>16) burst_words=16;
                if(burst_words>(4096-next_ar%4096)/8) burst_words=(4096-next_ar%4096)/8;
                check(ar_left>0 && M_AXI_ARADDR==next_ar && int'(M_AXI_ARLEN)+1==burst_words,
                    "all AR ranges contiguous, exact, with independent boundary splitting");
                ar_left=ar_left-8*burst_words;next_ar=next_ar+8*burst_words;
                if(commands==1) ar1=ar1+1;else ar2=ar2+1;
            end
            if(M_AXI_RVALID && M_AXI_RREADY) begin
                if(commands==1) raw1=raw1+1;else raw2=raw2+1;
            end
            if(in_we) begin
                check(phase==2 && int'(in_waddr)==input_writes &&
                    in_wdata===pattern(INPUT_BASE+8*input_writes,INPUT_SEED),"full input word/address sequence");
                input_writes=input_writes+1;
            end
            if(fc_start && fc_sel==0) begin
                fc_starts=fc_starts+1;
                check(mem_rd_start && phase==2 && input_writes==1440,"FC1 starts after complete input/Encoder");
            end
            if(commands==2 && prior_busy && !mem_rd_busy) fc_read_end=cycle;
            if(ctrl.state_reg==11) drain_cycles=drain_cycles+1;
            if(ctrl.state_reg==7) begin
                fc_cycles=fc_cycles+1;
                if(mem_rd_busy) fc_busy_cycles=fc_busy_cycles+1;
                if(prior_busy && !mem_rd_busy) fc_read_end=cycle;
                if(mem_rd_err || ctrl.run_error_reg==4) begin
                    if(error_at_push<0) error_at_push=pushes;
                    check(!fifo_we && mem_rd_ready && status_busy && !fc_start,"error stops FIFO writes and drains");
                    if(legacy_drain && mem_rd_busy) check(ctrl.state_next==7,"error cannot finish before M00 idle");
                    drain_cycles=drain_cycles+1;
                end else begin
                    check(fifo_we===(mem_rd_valid && !fifo_full) && mem_rd_ready===!fifo_full &&
                          fifo_wdata===mem_rd_data,"FC1 data/valid/full equations each cycle");
                    if(fifo_full) begin
                        full_samples=full_samples+1;full_run=full_run+1;
                        if(full_run>max_full_run) max_full_run=full_run;
                        check(!fifo_we && !M_AXI_RREADY,"full blocks push and actual AXI transfer");
                        if(mem_rd_valid) full_stalls=full_stalls+1;
                    end else full_run=0;
                    if(fc_done && done_edge==0) done_edge=cycle;
                    if(prior_busy && !mem_rd_busy) begin
                        fc_read_end=cycle;
                        if(done_edge!=0 && done_edge<cycle)
                            check(ctrl.fc_done_seen_reg,"earlier completion retained until busy falls");
                    end
                    check(ctrl.state_next==(((fc_done||ctrl.fc_done_seen_reg)&&!mem_rd_busy)?8:7),
                        "FC1 waits for both remembered/live done and read idle");
                    if(ctrl.state_next==8) check(fc_start && fc_sel==1 && !mem_rd_start,
                        "FC1 boundary emits exactly the FC2 START/select, even in isolated completion probes");
                end
            end
            if(fifo_we) begin
                check(phase==2 && !fifo_full && pushes<49152,"no full push or excess push");
                check(fifo_wdata===pattern(loaded_base+5936+8*pushes,weight_seed),"all FC1 words in exact order");
                check(fifo_wdata[63:32]!=(LOAD1_SEED^32'hA5C39E71) &&
                      fifo_wdata[63:32]!=(LOAD2_SEED^32'hA5C39E71),"no resident LOAD region word in FC1");
                pushes=pushes+1;
            end
            if(prior_state!=ctrl.state_reg || mem_rd_start || fc_start ||
                (prior_busy && !mem_rd_busy) || (fc_done && ctrl.state_reg==7))
                $fdisplay(events,"%0d,%0d,%0d,%0d,%0d,%b,%b,%b,%b,%b,%0d,%0d,%0d",
                    case_id,leg,phase,cycle,ctrl.state_reg,mem_rd_busy,mem_rd_err,fc_start,fc_done,
                    ctrl.fc_done_seen_reg,pushes,fc.pop_count,fc.count);
            prior_busy=mem_rd_busy;prior_state=ctrl.state_reg;
            #1;
            if(start_edge!=0 && !status_busy && finish_edge==0) finish_edge=cycle;
            if(fc_starts>0 && ctrl.state_reg==7 && cycle==fc_begin)
                check(!ctrl.fc_done_seen_reg,"FC START clears old completion on entry");
        end
    end
    task initialize_observation;
        begin
            reset_drain_observation;
            start_edge=0;finish_edge=0;commands=0;ar1=0;ar2=0;raw1=0;raw2=0;pushes=0;input_writes=0;
            load_starts=0;enc_starts=0;fc_starts=0;fc_cycles=0;fc_busy_cycles=0;full_samples=0;full_stalls=0;
            fc_begin=0;fc_read_end=0;done_edge=0;error_at_push=-1;drain_cycles=0;full_run=0;max_full_run=0;
            prior_mem_start=0;prior_fc_start=0;prior_busy=0;prior_state=0;injected=0;
            inject_before=memory.injection_count;done_before=fc.phase_dones[0];
        end
    endtask
    task wait_command;
        begin
            @(posedge clk);#2;check(status_busy && !status_done && status_error==0,"START clears display");
            @(negedge clk);reg_start=0;reg_cmd=32'hdeadbeef;reg_weight_addr=32'h2f000000;reg_input_addr=32'h2e000000;
            if(boundary_probe && phase==2) begin
                while(ctrl.state_reg!=8 || fc.active) begin
                    @(posedge clk);#2;check(cycle-start_edge<500000,"bounded FC1 boundary probe");
                end
                finish_edge=cycle;
                check(status_busy && !status_done && !mem_rd_busy && fc.pop_count==49152,
                    "isolated probe reaches FC2 boundary with all FIFO words consumed, no full-INFER claim");
            end else while(status_busy) begin @(posedge clk);#2;check(cycle-start_edge<500000,"bounded command completion");end
            check(!mem_rd_busy,"Top only finishes after M00 read completes");
            repeat(4) begin @(posedge clk);#2;end
            @(negedge clk);active=0;
            memory.check_quiescent;
            check(memory.violation_count==0 && loader.violations==0 && input_ram.violations==0 && fc.violations==0,
                "zero AXI/C12/consumer violations");
        end
    endtask
    task automatic do_load(input reg [31:0] base_value);
        begin
            @(negedge clk);initialize_observation;phase=1;expected_base=base_value;
            reg_cmd=1;reg_weight_addr=base_value;reg_start=1;active=1;cfg_ok=0;
            wait_command;
            check(status_done && status_error==0 && load_starts==1 && fc_starts==0,"LOAD successful without FC activity");
            check(ctrl.load_base_reg==base_value,"D06 base latched at LOAD launch");
            check(commands==2 && raw1==742 && raw2==2980 && loader.received_count==3722,"complete resident LOAD");
            for(integer j=0;j<3722;j=j+1)
                check(loader.received[j]===(j<742?pattern(base_value+8*j,LOAD1_SEED):
                    pattern(base_value+399152+8*(j-742),LOAD2_SEED)),"full Loader sequence");
            loaded_base=base_value;cfg_ok=1;
            $display("PASS: T-05 LOAD case=%0d leg=%0d base=%08h saved=%08h words=3722 AR1=%0d AR2=%0d cycles=%0d",
                case_id,leg,base_value,ctrl.load_base_reg,ar1,ar2,finish_edge-start_edge);
        end
    endtask
    task automatic do_infer(input reg [31:0] other_base);
        begin
            @(negedge clk);initialize_observation;phase=2;input_ram.begin_transfer;
            reg_cmd=0;reg_weight_addr=other_base;reg_input_addr=INPUT_BASE;reg_start=1;active=1;
            wait_command;
            expected_ar1=burst_count(INPUT_BASE,11520);expected_ar2=burst_count(loaded_base+5936,393216);
            check(commands==2 && ar1==expected_ar1 && ar2==expected_ar2 && raw1==1440 && raw2==49152,
                "full input/FC1 read coverage, computed burst count including alignment");
            check(input_writes==1440 && enc_starts==1 && fc_starts==1 && load_starts==0,"only intended block STARTs");
            check(ctrl.load_base_reg==loaded_base && ctrl.weight_addr_reg==other_base && other_base!=loaded_base,
                "D06 current INFER weight snapshot cannot replace saved LOAD base");
            for(integer j=0;j<1440;j=j+1) check(input_ram.mem[j]===pattern(INPUT_BASE+8*j,INPUT_SEED),"all stored input words");
            check(fc.push_count==pushes,"FIFO counted all pushes independently");
            for(integer j=0;j<pushes;j=j+1)
                check(fc.pushed[j]===pattern(loaded_base+5936+8*j,weight_seed),"entire pushed sequence");
            for(integer j=0;j<fc.pop_count;j=j+1)
                check(fc.consumed[j]===pattern(loaded_base+5936+8*j,weight_seed),"entire popped sequence in FIFO order");
            if(!fault) begin
                check((boundary_probe?status_busy:status_done) && status_error==0 && pushes==49152 && fc.pop_count==49152 && fc.count==0 && !fc.active,
                    "successful FC1 consumes all 49152 words and empties FIFO");
                check(fc.phase_dones[0]==done_before+1 && fc.sel_changed_cycles>0 && fc.selected_reg==(boundary_probe?0:2),
                    "one completion; START-latched selection ignores changing live selector");
                check(full_samples==fc.full_cycles && max_full_run==fc.max_full_run,"independent full statistics agree");
                if(fc.consume_mode==0) check(full_samples==0,"fast consumer never fills FIFO");
                else check(full_samples>0 && fc.max_count==512 && full_stalls>0,"real full/backpressure reached");
                if(fc.done_mode==2) begin
                    check(done_edge<fc_read_end,"forced early completion truly precedes busy falling");done_relation="before";
                end else if(fc.done_mode==1) begin
                    check(done_edge==fc_read_end,"forced completion coincides with busy falling");done_relation="same";
                end else begin check(done_edge>fc_read_end,"normal completion after busy falls");done_relation="after";end
                if(fc.done_width_cycles==1) check(!fc_done,"done is one-cycle pulse");
                else check(done_edge>0,"FC1 level done was observed exactly once before FC2 START cleared it");
            end else begin
                check(!status_done && status_error==4 && fc_starts==1 && memory.injection_count==inject_before+1,
                    "memory error recorded, no FC2/restart START");
                check(pushes==error_at_push && pushes<49152 && drain_cycles>0 && fc.active && full_samples>0,
                    "no writes after error; FC remains incomplete without an abort contract");
                done_relation="error_no_done";
            end
            if(fault && !legacy_drain) check(drain_entries==1 && drain_residence>0,"FC1 error passes shared drain");
            $display("OBS: R4 tb=fc1 case=%0d leg=%0d raw=%0d words=%0d discarded=%0d read_fall=%0d cycles=%0d done=%b error=%0d origin=%0d entries=%0d residence=%0d scope=%s",
                case_id,leg,raw2,pushes,drain_discarded,read_fall-start_edge,finish_edge-start_edge,status_done,status_error,drain_from,drain_entries,drain_residence,boundary_probe?"FC1_boundary":"full_INFER");
            infer_runs=infer_runs+1;
            $display("PASS: T-05 INFER case=%0d leg=%0d name=%s loaded=%08h current=%08h issued=%08h total_cycles=%0d FC1_cycles=%0d read_busy_cycles=%0d AR=%0d expected_AR=%0d pushes=%0d pops=%0d full_cycles=%0d max_full_run=%0d full_R_stalls=%0d done_relation=%s done_edge=%0d read_end=%0d done=%b error=%0d overflow=0 violations=0",
                case_id,leg,case_name,loaded_base,other_base,loaded_base+5936,finish_edge-start_edge,fc_cycles,
                fc_busy_cycles,ar2,expected_ar2,pushes,fc.pop_count,full_samples,max_full_run,full_stalls,
                done_relation,done_edge,fc_read_end,status_done,status_error);
        end
    endtask
    task automatic run_case(input integer id);
        begin
            @(negedge clk);active=0;resetn=0;reg_start=0;phase=0;repeat(3) @(negedge clk);
            case_id=id;boundary_probe=(id==5 || id==6);leg=0;fault=0;base_a=32'h1c000050;base_b=32'h1c100050;weight_seed=32'hfc1a0010;
            encoder.delay_cycles=5;fc.consume_mode=0;fc.consume_period=4;fc.done_mode=0;
            fc.done_delay_cycles=5;fc.done_width_cycles=1;fc.pause_after=1024;fc.pause_cycles=2000;fc.seed=32'h1234abcd;
            memory.ar_ready_mode=0;memory.r_gap_cycles=0;memory.ar_gap_cycles=0;
            case(id)
                0: case_name="fast_aligned";
                1: begin case_name="fast_blob_aligned";base_a=32'h1c000000;end
                2: begin case_name="slow_full";fc.consume_mode=1;end
                3: begin case_name="random_repeat";fc.consume_mode=2;end
                4: begin case_name="pause_resume";fc.consume_mode=3;end
                5: begin case_name="done_same";fc.done_mode=1;end
                6: begin case_name="done_before";fc.done_mode=2;end
                7: begin case_name="level_repeat";fc.done_width_cycles=0;end
                8: begin case_name="full_and_slave_stall";fc.consume_mode=1;
                    memory.ar_ready_mode=1;memory.ar_gap_cycles=7;memory.r_gap_cycles=1;end
                9: case_name="reload_base";
                10: begin case_name="RRESP_with_full";fc.consume_mode=1;fault=1;end
                default:$fatal(1,"invalid CASE");
            endcase
            fill_blob(base_a,32'hfc1a0010);fill_blob(base_b,32'hfc1b0020);
            memory.mem_fill(INPUT_BASE,11520,INPUT_SEED);
            resetn=1;do_load(base_a);do_infer(base_b);
            if(id==3 || id==7) begin
                repeats_full=full_samples;repeats_cycles=fc_cycles;leg=1;do_infer(base_b);
                check(full_samples==repeats_full && fc_cycles==repeats_cycles,"seed/level repeat has identical timing, counters reset");
            end
            if(id==9) begin
                leg=1;weight_seed=32'hfc1b0020;do_load(base_b);do_infer(base_a);
            end
            cases_done=cases_done+1;
        end
    endtask
    initial begin #50000000;$fatal(1,"FAIL: T-05 global deadline");end
    initial begin
        events=$fopen("top_fc1_events.csv","w");check(events!=0,"open trace");
        $fdisplay(events,"case,leg,phase,cycle,state,mem_busy,mem_err,fc_start,fc_done,done_seen,pushes,pops,count");
        if($value$plusargs("CASE=%d",selected)) begin
            check(selected>=0 && selected<=LAST_CASE,"valid selector");run_case(selected);
        end else for(integer c=0;c<=LAST_CASE;c=c+1) run_case(c);
        $display("PASS: T-05 ALL SELECTED cases=%0d INFER_runs=%0d selector=%0d violations=%0d",cases_done,infer_runs,selected,memory.violation_count);
        $fclose(events);$finish;
    end
endmodule
