`timescale 1ns / 1ps

// T-04 input/Encoder regression with T-06 FC1/FC2/FC3/write completion.
// Input cases/checks remain independent of subsequent FC and pose transfers.
module tb_top_infer;
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

    reg preparing_load=0;
    wire loader_ready;
    assign ld_ready = preparing_load ? loader_ready:1'b0; // IN_RD remains independent of Loader READY=0.
    loader_stub loader(.clk(clk),.resetn(resetn),.loader_start(loader_start),
        .ld_data(ld_data),.ld_valid(ld_valid),.ld_ready(loader_ready),.loader_done(loader_done),.loader_err(loader_err));
    in_ram_stub input_ram(.clk(clk),.resetn(resetn),.in_we(in_we),
        .in_waddr(in_waddr),.in_wdata(in_wdata));
    enc_stub encoder(.clk(clk),.resetn(resetn),.enc_start(enc_start),.enc_done(enc_done));
    fc_stub fc(.clk(clk),.resetn(resetn),.fc_start(fc_start),.fc_sel(fc_sel),
        .fifo_we(fifo_we),.fifo_wdata(fifo_wdata),.fifo_full(fifo_full),.fc_done(fc_done),.pose_data(pose_data),
        .fc_param_raddr(),.fc_param_rdata(96'd0),.fc_lut_raddr(),.fc_lut_rdata(8'd0),
        .fcw_raddr(),.fcw_rdata(64'd0),.flat_raddr(),.flat_rdata(64'd0));

    localparam integer LAST_CASE=12;
    localparam [31:0] SEED=32'h24681357, BEFORE_SEED=32'hbaad0001, AFTER_SEED=32'hbaad0002;
    // Seed the registered addresses with a real LOAD at base zero. The input
    // cases still drive cfg_ok (including NO_CFG) directly as in T-04.
    localparam [31:0] FC_BASE=32'd5936, FC_SEED=32'hfc04face;
    reg [31:0] base, next_ar;
    integer selected=-1, case_id, leg=0, cycle=0, tests=0, completed_cases=0;
    integer start_edge, finish_edge, read_edge, read_end, enc_edge, done_edge;
    integer commands, enc_pulses, ar_count, raw_beats, writes, enc_cycles;
    integer fc_commands, fc_before;
    integer ar_left, expected_beats, expected_bursts, boundary_shorts;
    integer equations, no_valid_checks, drain_cycles, error_at_word, expected_counter;
    integer fault_mode=0, injection_before, encoder_before, done_before, trace_file;
    bit active=0, prior_start, prior_enc_start, prior_busy, injected;
    reg [3:0] prior_state;
    string case_name;


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

    function automatic [63:0] pattern(input reg [31:0] addr, seed);
        pattern={seed^32'hA5C39E71,addr^seed};
    endfunction
    function automatic integer count_bursts(input reg [31:0] addr);
        integer remaining, n, b;
        reg [31:0] a;
        begin
            a=addr; remaining=1440; n=0;
            while (remaining>0) begin
                b=remaining<16 ? remaining:16;
                if (b>(4096-a%4096)/8) b=(4096-a%4096)/8;
                remaining=remaining-b; a=a+8*b; n=n+1;
            end
            count_bursts=n;
        end
    endfunction
    task automatic check(input bit ok,input string message);
        if (!ok) begin
            $display("FAIL: T-04 %s leg=%0d cycle=%0d state=%0d %s",case_name,leg,cycle,ctrl.state_reg,message);
            $fatal(1,"T-04 INFER mismatch");
        end
    endtask

    always @(negedge clk) begin
        if (active && !injected) begin
            if ((fault_mode==1 && ar_count==1) ||
                (fault_mode==2 && ar_count==expected_bursts-1)) begin
                memory.inject_rresp=2'b10;
                memory.inject_rresp_beat=fault_mode==1 ? 4:15;
                injected=1;
            end
        end
    end
    always @(posedge clk) begin
        cycle=cycle+1;
        if (resetn && active) begin
            observe_drain;
            expected_counter=int'(ctrl.beat_reg);
            if (reg_start && ctrl.state_reg==0) start_edge=cycle;
            check(!(prior_start && mem_rd_start),"read START one-cycle pulse");
            check(!(prior_enc_start && enc_start),"Encoder START one-cycle pulse");
            prior_start=mem_rd_start; prior_enc_start=enc_start;
            check({loader_start,ld_valid,ld_data}==='0,"LOAD outputs remain zero during INFER");
            if(ctrl.state_reg!=9 && ctrl.state_reg!=10)
                check({mem_wr_start,mem_wr_addr,mem_wr_bytes,mem_wr_data}==='0,"write outputs zero before FC3/WR");
            if(ctrl.state_reg==5 || ctrl.state_reg==6)
                check(fc_sel==0,"input/Encoder keeps FC selector zero");
            if (ctrl.state_reg!=7)
                check({fifo_we,fifo_wdata}==='0,"FIFO outputs remain zero outside FC1");
            if ((ctrl.state_reg!=6 && ctrl.state_reg!=7 && ctrl.state_reg!=8) ||
                (ctrl.state_reg==6 && !enc_done))
                check(!fc_start,"FC START only on completed Encoder transition");
            if (mem_rd_start) begin
                if (ctrl.state_reg==1) begin
                    check(commands==0 && fc_commands==0 && !mem_rd_busy,"one input read from DECODE while M00 idle");
                    check(mem_rd_addr===base && mem_rd_bytes==11520,"input START snapshot and exact bytes");
                    commands=commands+1; read_edge=cycle; expected_counter=0;
                end else begin
                    check(ctrl.state_reg==6 && enc_done && fc_start && !mem_rd_busy && fc_commands==0,
                        "one FC1 read on Encoder completion while M00 idle");
                    check(mem_rd_addr===FC_BASE && mem_rd_bytes==393216,"FC1 fixture address and exact bytes");
                    fc_commands=fc_commands+1;
                end
            end
            if(ctrl.state_reg==11) drain_cycles=drain_cycles+1;
            if (ctrl.state_reg==5) begin
                check(status_busy && mem_rd_ready===1'b1,"IN_RD always READY=1 even with Loader READY=0");
                check(in_waddr===ctrl.beat_reg && in_wdata===mem_rd_data,"IN_RD address/data equations");
                if (mem_rd_err || ctrl.run_error_reg==4) begin
                    check(!in_we && !enc_start,"error suppresses RAM writes and Encoder start");
                    if (error_at_word<0) error_at_word=writes;
                    drain_cycles=drain_cycles+1;
                    if (legacy_drain && mem_rd_busy) check(ctrl.state_next==5,"wait for M00 drain before FINISH");
                end else begin
                    check(in_we===mem_rd_valid,"IN_RD write enable equals valid");
                    equations=equations+1;
                    if (mem_rd_valid) begin
                        expected_counter=expected_counter+1;
                        check(!enc_start && ctrl.state_next==5,"valid beat takes priority over completion");
                    end else begin
                        no_valid_checks=no_valid_checks+1;
                        check(ctrl.state_next==((prior_busy && !mem_rd_busy)?6:5),"only falling busy may enter ENC");
                    end
                end
            end else if (ctrl.state_reg==6) begin
                enc_cycles=enc_cycles+1;
                check(status_busy && {mem_rd_ready,in_we,in_waddr,in_wdata,enc_start}==='0,
                    "ENC busy without input RAM activity");
                if (!enc_done)
                    check({mem_rd_start,mem_rd_addr,mem_rd_bytes}==='0,"ENC has no read command while waiting");
                else check(mem_rd_start && fc_start,"ENC done starts the FC1 fixture");
                check(ctrl.state_next==(enc_done?7:6),"ENC waits for done including a one-cycle pulse");
                if (enc_done && done_edge==0) done_edge=cycle;
            end
            if (fc_commands==0 && M_AXI_ARVALID && M_AXI_ARREADY) begin
                expected_beats=ar_left/8;
                if (expected_beats>16) expected_beats=16;
                if (expected_beats>(4096-next_ar%4096)/8) expected_beats=(4096-next_ar%4096)/8;
                check(ar_left>0 && M_AXI_ARADDR===next_ar && int'(M_AXI_ARLEN)+1==expected_beats,
                    "AR covers exact input range continuously without guards or overlap");
                if (expected_beats<16 && ar_left>8*expected_beats) begin
                    check((next_ar+8*expected_beats)%4096==0,"nonfinal short burst is a 4KiB split");
                    boundary_shorts=boundary_shorts+1;
                end
                ar_left=ar_left-8*expected_beats; next_ar=next_ar+8*expected_beats; ar_count=ar_count+1;
            end
            if (fc_commands==0 && M_AXI_RVALID && M_AXI_RREADY) raw_beats=raw_beats+1;
            if (in_we) begin
                check(writes<1440 && int'(in_waddr)==writes,"write addresses ordered 0..1439");
                check(in_wdata===pattern(base+8*writes,SEED),"all written words match address-dependent pattern");
                check(in_wdata[63:32]!=(BEFORE_SEED^32'hA5C39E71) &&
                      in_wdata[63:32]!=(AFTER_SEED^32'hA5C39E71),"neither guard pattern enters RAM");
                writes=writes+1;
            end
            if (fc_commands==0 && prior_busy && !mem_rd_busy) read_end=cycle;
            if (enc_start) begin
                enc_pulses=enc_pulses+1; enc_edge=cycle;
                check(ctrl.state_reg==5 && !mem_rd_err && prior_busy && !mem_rd_busy,
                    "Encoder starts on IN_RD exit after true busy falling edge");
                check(input_ram.write_count==1440 && writes==1440 && raw_beats==1440,
                    "all 1440 RAM words committed before Encoder START");
            end
            if (prior_state!=ctrl.state_reg || mem_rd_start || enc_start ||
                (prior_busy && !mem_rd_busy) || (ctrl.state_reg==6 && enc_done))
                $fdisplay(trace_file,"%0d,%0d,%s,%0d,%0d,%b,%b,%b,%b,%b,%0d,%0d,%0d",
                    case_id,leg,case_name,cycle,ctrl.state_reg,status_busy,mem_rd_busy,mem_rd_err,
                    enc_start,enc_done,raw_beats,writes,ar_count);
            prior_state=ctrl.state_reg; prior_busy=mem_rd_busy;
            #1;
            if(fc_commands==0)
                check(int'(ctrl.beat_reg)==expected_counter,"input beat increments only on normal valid, clears at input command");
            if (start_edge!=0 && !status_busy && finish_edge==0) finish_edge=cycle;
        end
    end

    task execute_transfer;
        integer last_write_cycle, expected_error;
        begin
            reset_drain_observation;
            // Falling-edge setup avoids any sampling race with RAM/model monitors.
            input_ram.begin_transfer;
            commands=0; enc_pulses=0; ar_count=0; raw_beats=0; writes=0; enc_cycles=0;
            fc_commands=0; fc_before=fc.accepted_starts;
            equations=0; no_valid_checks=0; drain_cycles=0; error_at_word=-1;
            start_edge=0; finish_edge=0; read_edge=0; read_end=0; enc_edge=0; done_edge=0;
            ar_left=11520; next_ar=base; boundary_shorts=0;
            prior_start=0; prior_enc_start=0; prior_busy=0; prior_state=0; injected=0;
            expected_bursts=count_bursts(base); injection_before=memory.injection_count;
            encoder_before=encoder.accepted_starts; done_before=encoder.done_count;
            memory.mem_fill(base-8,8,BEFORE_SEED);
            memory.mem_fill(base,11520,SEED);
            memory.mem_fill(base+11520,8,AFTER_SEED);
            memory.mem_fill(FC_BASE,393216,FC_SEED);
            reg_cmd=0; reg_input_addr=base; reg_output_addr=32'h1e000000; reg_start=1; active=1;
            @(posedge clk); #2;
            check(status_busy && ctrl.state_reg==1 && !status_done && status_error==0,"accepted START clears display and enters DECODE");
            @(negedge clk); reg_start=0; reg_input_addr=32'hbad00000; reg_cmd=32'hdeadbeef;
            while (status_busy) begin
                @(posedge clk); #2;
                check(cycle-start_edge<300000,"bounded INFER completion including FC1");
            end
            check(!mem_rd_busy && !mem_wr_busy,"Top cannot finish before M00 read/write completes");
            repeat(3) begin @(posedge clk); #2; end
            @(negedge clk); active=0;
            expected_error=!cfg_ok ? 2:(fault_mode!=0 ? 4:0);
            check(status_done== (expected_error==0) && status_error==expected_error,"sticky success/error result");
            check(input_ram.write_count==writes,"RAM independently counted every write");
            last_write_cycle=-1;
            for(integer j=0;j<writes;j=j+1) begin
                check(input_ram.written[j] && input_ram.mem[j]===pattern(base+8*j,SEED) &&
                    input_ram.address_log[j]==j && input_ram.data_log[j]===pattern(base+8*j,SEED),
                    "full stored address/value log and RAM comparison");
                check(input_ram.cycle_log[j]>last_write_cycle,"each write has a distinct increasing cycle");
                last_write_cycle=input_ram.cycle_log[j];
            end
            if (!cfg_ok) begin
                check(commands==0 && ar_count==0 && raw_beats==0 && writes==0 && enc_pulses==0,
                    "NO_CFG rejects before any memory/Encoder activity");
                check(finish_edge-start_edge==2,"NO_CFG retains two-cycle busy");
            end else begin
                check(commands==1 && ar_count==expected_bursts && ar_left==0 && raw_beats==1440,
                    "one command, all calculated bursts and 1440 R beats completed");
                check(memory.injection_count-injection_before==(fault_mode!=0?1:0),"requested fault actually injected once");
                if (fault_mode==0) begin
                    check(writes==1440 && enc_pulses==1 && encoder.accepted_starts==encoder_before+1,
                        "complete RAM then exactly one accepted Encoder START");
                    check(encoder.done_count==done_before+1 && encoder.done_cycle-encoder.start_cycle==encoder.delay_cycles,
                        "configured synchronous Encoder completion delay measured exactly");
                    check(enc_cycles==encoder.delay_cycles+1 && done_edge!=0,"ENC observes earliest/delayed completion");
                    if (encoder.done_width_cycles==1) check(!enc_done,"one-cycle done returned low");
                    else check(enc_done,"level done remains high until new START/reset");
                end else begin
                    check(enc_pulses==0 && enc_cycles==0 && encoder.accepted_starts==encoder_before,
                        "memory error cannot start Encoder");
                    check(drain_cycles>0 && error_at_word==writes,"no RAM writes after error observation");
                    check(writes==(fault_mode==1?21:1440),"registered M00 error includes faulting beat, suppresses subsequent writes");
                end
            end
            check(fc_commands==(expected_error==0?1:0) &&
                  fc.accepted_starts-fc_before==3*fc_commands,"FC1/2/3 only run after successful input/Encoder");
            if (expected_error==0)
                check(fc.push_count==49152 && fc.pop_count==49152 && fc.count==0 && !fc.active,
                    "FC1 completion fixture consumed all words before Top finished");
            check(memory.mem_word(base-8)===pattern(base-8,BEFORE_SEED) &&
                  memory.mem_word(base+11520)===pattern(base+11520,AFTER_SEED),"both guard words preserved");
            check(encoder.ignored_starts==0 && input_ram.violations==0 && memory.violation_count==0 && fc.violations==0,
                "no repeated Encoder starts or RAM/AXI/C12 violations");
            memory.check_quiescent;
            if(fault_mode!=0 && !legacy_drain) check(drain_entries==1 && drain_residence>0,"input error passes ERR_DRAIN");
            $display("OBS: R4 tb=infer case=%0d leg=%0d raw=%0d words=%0d discarded=%0d read_fall=%0d cycles=%0d done=%b error=%0d origin=%0d entries=%0d residence=%0d",
                case_id,leg,raw_beats,writes,drain_discarded,(read_fall==0?0:read_fall-start_edge),finish_edge-start_edge,status_done,status_error,drain_from,drain_entries,drain_residence);
            tests=tests+1;
            $display("PASS: T-04 case=%0d leg=%0d name=%s base=%08h total_cycles=%0d input_cycles=%0d enc_delay=%0d enc_cycles=%0d commands=%0d AR=%0d expected_AR=%0d boundary_shorts=%0d R=%0d RAM_words=%0d enc_start=%0d equations=%0d no_valid=%0d drain_cycles=%0d discarded=%0d done=%b error=%0d violations=0",
                case_id,leg,case_name,base,finish_edge-start_edge,read_end-read_edge,
                encoder.delay_cycles,enc_cycles,commands,ar_count,cfg_ok?expected_bursts:0,boundary_shorts,
                raw_beats,writes,enc_pulses,equations,no_valid_checks,drain_cycles,raw_beats-writes,status_done,status_error);
            $display("PASS: T-06 input regression case=%0d leg=%0d FC_commands=%0d FC_pushes=%0d FC_pops=%0d violations=%0d",
                case_id,leg,fc_commands,fc.push_count,fc.pop_count,fc.violations);
        end
    endtask

    task prepare_addresses;
        integer began;
        begin
            @(negedge clk); preparing_load=1;reg_cmd=1;reg_weight_addr=0;reg_start=1;began=cycle;
            @(posedge clk);#2;check(status_busy,"fixture LOAD accepted");
            @(negedge clk);reg_start=0;
            while(status_busy) begin @(posedge clk);#2;check(cycle-began<30000,"fixture LOAD bounded");end
            check(status_done && status_error==0 && loader.received_count==3722,"fixture resident LOAD complete");
            check(ctrl.ld2_addr_reg==399152 && ctrl.fc1_addr_reg==FC_BASE,"LOAD populated precomputed addresses");
            memory.check_quiescent;
            @(negedge clk);preparing_load=0;
        end
    endtask

    task automatic run_case(input integer id);
        begin
            @(negedge clk); active=0; resetn=0; reg_start=0; reg_clear_status=0;
            repeat(3) @(negedge clk);
            case_id=id; leg=0; base=32'h1d000000; cfg_ok=1; fault_mode=0;
            encoder.delay_cycles=5; encoder.done_width_cycles=1;
            memory.ar_ready_mode=0; memory.ar_gap_cycles=0; memory.r_gap_cycles=0;
            memory.ddr_latency_cycles=0;
            case(id)
                0: begin case_name="aligned_delay0"; encoder.delay_cycles=0; end
                1: case_name="aligned_delay5";
                2: begin case_name="aligned_delay100"; encoder.delay_cycles=100; end
                3: begin case_name="aligned_delay1000"; encoder.delay_cycles=1000; end
                4: begin case_name="unaligned_008"; base=base+8; end
                5: begin case_name="boundary_ff8_stalls"; base=base+4088;
                    memory.ar_ready_mode=1; memory.ar_gap_cycles=7; memory.r_gap_cycles=2; end
                6: begin case_name="random_AR_and_R_gaps"; memory.ar_ready_mode=2;
                    memory.ar_seed=32'h23456789; memory.r_gap_cycles=1; end
                7: begin case_name="level_done"; encoder.done_width_cycles=0; end
                8: begin case_name="NO_CFG"; cfg_ok=0; end
                9: begin case_name="RRESP_middle"; fault_mode=1; end
                10: begin case_name="RRESP_last"; fault_mode=2; end
                11: begin case_name="level_done_repeat"; encoder.done_width_cycles=0; end
                12: begin case_name="error_then_restart"; fault_mode=1; end
                default: $fatal(1,"invalid CASE");
            endcase
            resetn=1;
            prepare_addresses;
            // LOAD preparation must not consume the input case's PRNG sequence.
            if(id==6) memory.ar_seed=32'h23456789;
            @(negedge clk); execute_transfer;
            if (id==11 || id==12) begin
                // Normal level-done repetition stays reset-free. D08 memory-error
                // recovery now explicitly resets all TB endpoints and reloads.
                if(id==12) begin
                    @(negedge clk);resetn=0;cfg_ok=0;repeat(3) @(negedge clk);
                    resetn=1;prepare_addresses;cfg_ok=1;
                end
                leg=1; fault_mode=0;
                @(negedge clk); execute_transfer;
            end
            completed_cases=completed_cases+1;
        end
    endtask

    initial begin #20000000; $fatal(1,"FAIL: T-04 global deadline including FC1"); end
    initial begin
        trace_file=$fopen("top_infer_events.csv","w");
        check(trace_file!=0,"open trace");
        $fdisplay(trace_file,"case,leg,name,cycle,state,top_busy,mem_busy,mem_err,enc_start,enc_done,R,RAM,AR");
        if ($value$plusargs("CASE=%d",selected)) begin
            check(selected>=0 && selected<=LAST_CASE,"valid CASE selector");
            run_case(selected);
        end else begin
            // Default execution covers EVERY case, not just CASE=0.
            for(integer c=0;c<=LAST_CASE;c=c+1) run_case(c);
        end
        $display("PASS: T-04 N1-N8 ALL SELECTED CHECKS cases=%0d runs=%0d selector=%0d AXI_C12_violations=%0d RAM_violations=%0d",
            completed_cases,tests,selected,memory.violation_count,input_ram.violations);
        $fclose(trace_file); $finish;
    end
endmodule
