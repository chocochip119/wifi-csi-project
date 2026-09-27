`timescale 1ns / 1ps

// T-03 Top/real-M00 integration fixture. Existing memory RTL/model unchanged.
module tb_top_load;
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
    assign enc_done = '0;
    wire  in_we;
    wire [10:0] in_waddr;
    wire [63:0] in_wdata;
    wire  fc_start;
    wire  fc_done;
    assign fc_done = '0;
    wire [1:0] fc_sel;
    wire  fifo_we;
    wire [63:0] fifo_wdata;
    wire  fifo_full;
    assign fifo_full = '0;
    wire [191:0] pose_data;
    assign pose_data = '0;
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
        .ld_data(ld_data),.ld_valid(ld_valid),.ld_ready(ld_ready),
        .loader_done(loader_done),.loader_err(loader_err));
    localparam [31:0] BASE=32'h1c000000;
    localparam [31:0] SEED1=32'haaaa0001, SEED_SKIP=32'hbbbb0002, SEED2=32'hcccc0003;
    integer selected=0, cycle=0, start_edge=0, finish_edge=0;
    integer commands=0, loader_pulses=0, ar1=0, ar2=0, raw_beats=0, delivered=0;
    integer waiting=0, last_first_beat=0, raw_last=0, done_edge=0;
    integer equation_checks=0, held_cycles=0, error_part=0, ar_left=0, ar_expected;
    integer ar_injected=0, events, injection_before;
    reg [31:0] next_ar_addr;
    bit active=0, done_seen=0, prior_start=0, prior_loader_start=0, prior_busy=0;
    bit prior_loader_done=0, injected=0, early_error=0;
    reg [3:0] prior_state=0;
    reg [63:0] expected_data;
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

    function automatic [63:0] pattern(input reg [31:0] addr,seed);
        pattern={seed^32'hA5C39E71,addr^seed};
    endfunction
    task automatic check(input bit ok,input string message);
        if (!ok) begin
            $display("FAIL: %s cycle=%0d state=%0d %s",case_name,cycle,ctrl.state_reg,message);
            $fatal(1,"T-03 integrated LOAD mismatch");
        end
    endtask

    always @(negedge clk) begin
        if (active && !injected) begin
            if ((error_part==1 && ar1==1) || (error_part==2 && ar2==1)) begin
                memory.inject_rresp=2'b10; memory.inject_rresp_beat=4; injected=1;
            end
            // Last beat of request 1: error and busy-fall must prefer error.
            if (error_part==3 && ar1==46) begin
                memory.inject_rresp=2'b10; memory.inject_rresp_beat=5; injected=1;
            end
        end
    end

    always @(posedge clk) begin
        cycle=cycle+1;
        if (resetn && active) begin
            observe_drain;
            check(!(prior_start && mem_rd_start),"mem_rd_start is one cycle");
            check(!(prior_loader_start && loader_start),"loader_start is one cycle");
            check(!(prior_loader_done && loader_done),"loader_done is one cycle");
            prior_start=mem_rd_start; prior_loader_start=loader_start; prior_loader_done=loader_done;
            check({mem_wr_start,enc_start,in_we,fc_start,fifo_we}===5'b00000,"future compute/write paths stay inactive");
            if (loader_start) begin
                loader_pulses=loader_pulses+1;
                check(mem_rd_start && commands==0 && ctrl.state_reg==1,"same-edge Loader/read start in DECODE");
            end
            if (mem_rd_start) begin
                check(!mem_rd_busy,"M00 command issued only when idle");
                if (commands==0) begin
                    check(mem_rd_addr===BASE && mem_rd_bytes==5936,"request1 uses START snapshot");
                    check(loader_start,"first command also starts Loader");
                    next_ar_addr=BASE; ar_left=5936;
                end else begin
                    check(commands==1 && mem_rd_addr===BASE+399152 && mem_rd_bytes==23840,"request2 exact offset and size");
                    check(prior_busy && !mem_rd_busy && raw_beats==742 && last_first_beat<cycle,
                        "request2 only after request1 falling busy and final accepted beat");
                    next_ar_addr=BASE+399152; ar_left=23840;
                end
                commands=commands+1;
            end
            if (ctrl.state_reg==2 || ctrl.state_reg==3) begin
                if (!mem_rd_err && ctrl.run_error_reg!=4) begin
                    check(ld_valid===mem_rd_valid && ld_data===mem_rd_data && mem_rd_ready===ld_ready,
                        "every normal LOAD clock obeys data/valid/ready equations");
                    equation_checks=equation_checks+1;
                end
                if (mem_rd_err || ctrl.run_error_reg==4) begin
                    check(!mem_rd_start && !ld_valid && mem_rd_ready && status_busy,
                        "error detection gates Loader and keeps Top busy");
                    if (legacy_drain && mem_rd_busy) check(ctrl.state_next==ctrl.state_reg,
                        "drain cannot leave LD_RD before M00 completion");
                end
            end
            if (ctrl.state_reg==4) begin
                waiting=waiting+1;
                check(status_busy && !mem_rd_start && !ld_valid && !mem_rd_ready,
                    "LD_WAIT stays busy without read or data outputs");
            end
            if (M_AXI_ARVALID && M_AXI_ARREADY) begin
                ar_expected=ar_left/8;
                if (ar_expected>16) ar_expected=16;
                if (ar_expected>(4096-(next_ar_addr%4096))/8) ar_expected=(4096-(next_ar_addr%4096))/8;
                check(ar_left>0 && M_AXI_ARADDR===next_ar_addr && int'(M_AXI_ARLEN)+1==ar_expected,
                    "all AR ranges independently cover only the requested resident regions");
                next_ar_addr=next_ar_addr+ar_expected*8; ar_left=ar_left-ar_expected*8;
                if (commands==1) ar1=ar1+1; else ar2=ar2+1;
            end
            if (M_AXI_RVALID && M_AXI_RREADY) begin
                raw_beats=raw_beats+1; raw_last=cycle;
                if (raw_beats==742) last_first_beat=cycle;
            end
            if (ld_valid && !ld_ready) held_cycles=held_cycles+1;
            if (ld_valid && ld_ready) begin
                check(delivered<3722,"no extra Loader beat");
                expected_data=delivered<742 ? pattern(BASE+8*delivered,SEED1) :
                    pattern(BASE+399152+8*(delivered-742),SEED2);
                check(ld_data===expected_data,"end-to-end word order and resident-region pattern");
                check(ld_data[63:32] !== (SEED_SKIP^32'hA5C39E71),"no skipped FC1 weight word delivered");
                delivered=delivered+1;
            end
            if (loader_done) begin done_seen=1; done_edge=cycle; end
            if (prior_state!=ctrl.state_reg || mem_rd_start || loader_done || (prior_busy && !mem_rd_busy))
                $fdisplay(events,"%s,%0d,%0d,%b,%b,%b,%b,%b,%0d,%0d,%0d,%0d",
                    case_name,cycle,ctrl.state_reg,status_busy,mem_rd_busy,mem_rd_err,mem_rd_start,
                    loader_done,raw_beats,delivered,ar1,ar2);
            // Transition checks use the values that will be sampled this edge.
            if (ctrl.state_reg==2 && !mem_rd_err && ctrl.run_error_reg!=4 && ctrl.state_next==3)
                check(prior_busy && !mem_rd_busy,"LD_RD1 exit requires actual falling busy");
            if (ctrl.state_reg==3 && ctrl.state_next==4)
                check(prior_busy && !mem_rd_busy && !mem_rd_start,"LD_RD2 -> LD_WAIT on falling busy only");
            prior_state=ctrl.state_reg; prior_busy=mem_rd_busy;
            #1;
            if (start_edge!=0 && !status_busy && finish_edge==0) finish_edge=cycle;
        end
    end

    initial begin #20000000; $fatal(1,"FAIL: T-03 global deadline"); end
    task automatic run_case(input integer id);
        begin
        @(negedge clk);active=0;resetn=0;reg_start=0;
        selected=id;commands=0;loader_pulses=0;ar1=0;ar2=0;raw_beats=0;delivered=0;
        start_edge=0;finish_edge=0;waiting=0;last_first_beat=0;raw_last=0;done_edge=0;
        equation_checks=0;held_cycles=0;error_part=0;ar_left=0;done_seen=0;
        prior_start=0;prior_loader_start=0;prior_busy=0;prior_loader_done=0;injected=0;prior_state=0;
        reset_drain_observation;injection_before=memory.injection_count;
        loader.ready_mode=0;loader.done_delay_cycles=10;loader.inject_error=0;
        memory.ar_ready_mode=0;memory.ar_gap_cycles=0;memory.r_gap_cycles=0;
        events=$fopen($sformatf("top_load_case%0d.csv",selected),"w");
        check(events!=0,"open transition trace");
        $fdisplay(events,"case,cycle,state,top_busy,mem_busy,mem_err,mem_start,loader_done,raw_R,loader_words,AR1,AR2");
        case(selected)
            0: begin case_name="always_ready"; loader.done_delay_cycles=10; end
            1: begin case_name="fixed_8"; loader.ready_mode=1; loader.done_delay_cycles=10; end
            2: begin case_name="typed_and_slave_stall"; loader.ready_mode=2; loader.done_delay_cycles=20;
                memory.ar_ready_mode=1; memory.ar_gap_cycles=7; memory.r_gap_cycles=2; end
            3: begin case_name="random_and_slave_stall"; loader.ready_mode=3; loader.done_delay_cycles=5;
                memory.ar_ready_mode=2; memory.ar_seed=32'h13572468; memory.r_gap_cycles=1; end
            4: begin case_name="blob_error"; loader.inject_error=1; loader.done_delay_cycles=7; end
            5: begin case_name="immediate_done"; loader.done_delay_cycles=0; end
            6: begin case_name="read_error_part1"; error_part=1; end
            7: begin case_name="read_error_part2"; error_part=2; end
            8: begin case_name="read_error_last_part1"; error_part=3; end
            9: begin case_name="immediate_done_error"; loader.done_delay_cycles=0; loader.inject_error=1; end
            default: $fatal(1,"invalid CASE");
        endcase
        memory.mem_fill(BASE,5936,SEED1);
        memory.mem_fill(BASE+5936,393216,SEED_SKIP);
        memory.mem_fill(BASE+399152,23840,SEED2);
        repeat(3) @(negedge clk);
        resetn=1; reg_cmd=1; reg_weight_addr=BASE;
        @(negedge clk); active=1; reg_start=1;
        @(posedge clk); #2; start_edge=cycle;
        check(status_busy && ctrl.state_reg==1,"accepted START enters DECODE with busy high");
        @(negedge clk); reg_start=0; reg_weight_addr=32'hbad00000; reg_cmd=32'hdeadbeef;
        while(status_busy) begin
            @(posedge clk); #2;
            check(cycle-start_edge<100000,"LOAD completion deadline (possible lost Loader done)");
        end
        // The approved temporary drain must finish the read before Top exits.
        check(!mem_rd_busy,"Top reports completion only after memory drain");
        repeat(2) begin @(posedge clk); #2; end
        while(mem_rd_busy) begin
            @(posedge clk); #2;
            check(cycle-finish_edge<10000,"L7 M00 cannot drain if Top leaves mem_rd_ready low");
        end
        @(negedge clk); active=0;
        check(loader_pulses==1 && loader.start_count==1,"one Loader start per LOAD");
        check(loader.received_count==delivered,"collected Loader count matches all handshakes");
        if (error_part==0) begin
            check(commands==2 && raw_beats==3722 && delivered==3722,"two complete read regions, all Loader beats");
            check(ar1==47 && ar2==187,"exact AR burst counts 47+187=234");
            check(done_seen && loader.done_count==1 && waiting>0,"one Loader done and actual LD_WAIT residence");
            check(status_done===!loader.inject_error && status_error==(loader.inject_error?3:0),"Loader success/BLOB_ERR result");
            for(integer j=0;j<3722;j=j+1) begin
                expected_data=j<742 ? pattern(BASE+8*j,SEED1) : pattern(BASE+399152+8*(j-742),SEED2);
                check(loader.received[j]===expected_data,"stored complete Loader sequence comparison");
            end
            if (selected==1 || selected==2) check(loader.max_low_run==8,"eight consecutive low ready cycles observed");
            if (selected==0 || selected==1) check(waiting>=9,"delayed done forces LD_WAIT to wait");
        end else begin
            check(!status_done && status_error==4 && waiting==0 && !done_seen,"memory error reaches FINISH without waiting for Loader");
            check(delivered<3722 && loader.done_count==0,"error leaves incomplete Loader payload");
            check(raw_beats==(error_part==2?3722:742),"M00 drains complete command after response error");
            check(commands==(error_part==2?2:1),"no next read after earlier region failure");
            check(memory.injection_count-injection_before==1,"one RRESP fault actually injected");
        end
        memory.check_quiescent;
        check(memory.violation_count==0 && loader.violations==0,"zero AXI/C12/Loader protocol violations");
        $display("PASS: T-03 %s L1-L8 cycles=%0d commands=%0d Loader_start=%0d AR1=%0d AR2=%0d R_beats=%0d compared_words=%0d LD_WAIT_cycles=%0d max_ready_low=%0d held_valid=%0d equations=%0d done=%b error=%0d violations=0",
            case_name,finish_edge-start_edge,commands,loader_pulses,ar1,ar2,raw_beats,delivered,
            waiting,loader.max_low_run,held_cycles,equation_checks,status_done,status_error);
        $display("OBS: R4 tb=load case=%0d leg=0 raw=%0d words=%0d discarded=%0d read_fall=%0d cycles=%0d done=%b error=%0d origin=%0d entries=%0d residence=%0d",
            selected,raw_beats,delivered,drain_discarded,read_fall-start_edge,finish_edge-start_edge,status_done,status_error,drain_from,drain_entries,drain_residence);
        if(error_part!=0 && !legacy_drain) check(drain_entries==1 && drain_residence>0,"R1 read error traversed shared drain exactly once");
        $fclose(events);
        end
    endtask
    integer selection=-1;
    initial begin
        if($value$plusargs("CASE=%d",selection)) begin
            check(selection>=0 && selection<=9,"valid CASE");run_case(selection);
        end else for(integer c=0;c<10;c=c+1) run_case(c);
        $display("PASS: T-07 LOAD ALL SELECTED cases=%0d selector=%0d",selection<0?10:1,selection);
        $finish;
    end
endmodule
