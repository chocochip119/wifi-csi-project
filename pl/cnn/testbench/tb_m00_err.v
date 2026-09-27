`timescale 1ns / 1ps

// T-02d independent error fixture. Existing sources are never included/edited.
// The watchdog instance changes only the public RTL parameter.
module m00_err_fixture #(parameter integer WD=0);
    reg clk = 0, resetn = 0;
    always #5 clk = ~clk;
    reg mem_rd_start = 0, mem_rd_ready = 1;
    reg [31:0] mem_rd_addr = 0;
    reg [19:0] mem_rd_bytes = 0;
    wire mem_rd_busy, mem_rd_valid, mem_rd_err;
    wire [63:0] mem_rd_data;
    reg mem_wr_start = 0;
    reg [31:0] mem_wr_addr = 0;
    reg [19:0] mem_wr_bytes = 0;
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
    pose_cnn_v1_0_M00_AXI #(.WATCHDOG_CYCLES(WD)) dut (
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



    integer producer_index = 0;
    reg [31:0] rbase, wbase, rseed, wseed;
    integer rbytes, wbytes;
    function automatic [63:0] pattern(input reg [31:0] addr, seed);
        pattern = {seed ^ 32'hA5C3_9E71, addr ^ seed};
    endfunction
    assign mem_wr_data = pattern(wbase + 8*producer_index, wseed);
    always @(posedge clk) begin
        if (!resetn) producer_index <= 0;
        else if (mem_wr_start && !mem_wr_busy) producer_index <= 0;
        else if (mem_wr_ready) producer_index <= producer_index + 1;
    end

    integer cycle = 0, cases = 0, inj_before, trace;
    bit enabled = 0, rmon = 0, wmon = 0, rstarted, wstarted, rdone, wdone;
    bit invalid_active = 0;
    string label;
    integer rn, wn, ar, aw, bn, ri_words, wi_words;
    integer rs, ws, rf, wf, rbusy, wbusy, re_high, we_high;
    integer re_first, we_first, rbad, bbad, rbad_first, bbad_first;
    integer rbad_burst, bbad_burst, rwait_run, wwait_run, re_waits, we_waits;
    integer rkind, wkind, rtarget, wtarget, fault_mode;
    bit rarmed, warmed, rexpect, wexpect, prior_re = 0, prior_we = 0;
    reg [63:0] rcollected [0:511], wcollected [0:511];
    bit raccept, waccept, rprebusy, wprebusy, rbad_edge, bbad_edge;
    bit rwaiting, wwaiting;
    integer n;

    task automatic check(input bit ok, input string message);
        if (!ok) begin
            $display("FAIL: WD=%0d %s cycle=%0d %s", WD, label, cycle, message);
            $fatal(1, "T-02d check failed");
        end
    endtask

    function automatic integer plan(input reg [31:0] addr, input integer bytes);
        integer v, boundary;
        begin
            v = bytes/8; boundary = (4096-(addr%4096))/8;
            if (v > 16) v = 16;
            if (v > boundary) v = boundary;
            plan = v;
        end
    endfunction

    // Public injection controls are armed before the target address handshake.
    // No checker code is waived: model-owned bad R/B responses are NOT master
    // violations in C1-C12. Any model checker violation terminates this test.
    always @(negedge clk) begin
        if (resetn && enabled) begin
            if (rmon && rkind != 0 && !rarmed && ar == rtarget-1) begin
                case (rkind)
                    1: begin memory.inject_rresp = 2'b10; memory.inject_rresp_beat = 4; end
                    2: memory.inject_rid = 1;
                    3: memory.inject_rlast_mode = fault_mode;
                endcase
                rarmed = 1;
            end
            if (wmon && wkind != 0 && !warmed && aw == wtarget-1) begin
                if (wkind == 1) memory.inject_bresp = 2'b10;
                else memory.inject_bid = 1;
                warmed = 1;
            end
        end
    end

    // Counters sample the pre-NBA bus; errors/state are checked after NBA.
    // The only hierarchical DUT state reads are for observation/RD_FAULT/reset.
    always @(posedge clk) begin
        cycle = cycle + 1;
        if (!resetn) begin prior_re = 0; prior_we = 0; end
        else if (enabled) begin
            raccept = mem_rd_start && !mem_rd_busy;
            waccept = mem_wr_start && !mem_wr_busy;
            rprebusy = mem_rd_busy; wprebusy = mem_wr_busy;
            rbad_edge = M_AXI_RVALID && M_AXI_RREADY &&
                (M_AXI_RRESP != 0 || M_AXI_RID != 0);
            bbad_edge = M_AXI_BVALID && M_AXI_BREADY &&
                (M_AXI_BRESP != 0 || M_AXI_BID != 0);
            rwaiting = (M_AXI_ARVALID && !M_AXI_ARREADY) ||
                (ar > 0 && rn < ri_words && mem_rd_ready && !M_AXI_RVALID);
            wwaiting = ((M_AXI_AWVALID || M_AXI_WVALID) &&
                !(M_AXI_AWVALID && M_AXI_AWREADY) && !(M_AXI_WVALID && M_AXI_WREADY)) ||
                (M_AXI_BREADY && !M_AXI_BVALID);
            check(memory.violation_count == 0, "no permitted M00 protocol violation");
            check(mem_wr_ready === (M_AXI_WVALID && M_AXI_WREADY), "ready equals each W acceptance");
            if (invalid_active)
                check(!M_AXI_ARVALID && !M_AXI_AWVALID && !M_AXI_WVALID,
                      "invalid command never offers an AXI request, even without READY");
            if (rmon) begin
                if (raccept) begin rstarted = 1; rs = cycle; end
                if (rprebusy) rbusy = rbusy+1;
                if (rprebusy && mem_rd_err) re_high = re_high+1;
                if (rwaiting) rwait_run = rwait_run+1; else rwait_run = 0;
                if (M_AXI_ARVALID && M_AXI_ARREADY) begin
                    n = plan(rbase+8*ri_words, rbytes-8*ri_words);
                    check(M_AXI_ARADDR === rbase+8*ri_words && int'(M_AXI_ARLEN)+1 == n,
                        "read address/length covers original command after fault");
                    ri_words = ri_words+n; ar = ar+1;
                end
                if (mem_rd_valid && mem_rd_ready) begin
                    check(rn < rbytes/8, "no extra read word");
                    check(mem_rd_data === M_AXI_RDATA, "core read data equals bus");
                    rcollected[rn] = mem_rd_data;
                    if (rbad_edge) begin
                        rbad = rbad+1;
                        if (rbad_first == 0) begin rbad_first = rn+1; rbad_burst = ar; end
                    end
                    rn = rn+1;
                end
            end
            if (wmon) begin
                if (waccept) begin wstarted = 1; ws = cycle; end
                if (wprebusy) wbusy = wbusy+1;
                if (wprebusy && mem_wr_err) we_high = we_high+1;
                if (wwaiting) wwait_run = wwait_run+1; else wwait_run = 0;
                if (M_AXI_AWVALID && M_AXI_AWREADY) begin
                    n = plan(wbase+8*wi_words, wbytes-8*wi_words);
                    check(M_AXI_AWADDR === wbase+8*wi_words && int'(M_AXI_AWLEN)+1 == n,
                        "write address/length covers original command after fault");
                    wi_words = wi_words+n; aw = aw+1;
                end
                if (mem_wr_ready) begin
                    check(wn < wbytes/8 && producer_index == wn, "one producer advance per W beat");
                    wcollected[wn] = M_AXI_WDATA; wn = wn+1;
                end
                if (M_AXI_BVALID && M_AXI_BREADY) begin
                    bn = bn+1;
                    if (bbad_edge) begin
                        bbad = bbad+1;
                        if (bbad_first == 0) begin bbad_first = wn; bbad_burst = bn; end
                    end
                end
            end
            $fdisplay(trace, "%s,%0d,%b,%b,%b,%b,%b,%b,%b,%b,%b,%b,%b,%b,%b,%b,%b,%b,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                label, cycle, resetn, mem_rd_start, mem_wr_start, mem_rd_busy, mem_wr_busy,
                mem_rd_err, mem_wr_err, M_AXI_ARVALID, M_AXI_ARREADY, M_AXI_RVALID, M_AXI_RREADY,
                M_AXI_AWVALID, M_AXI_AWREADY, M_AXI_WVALID, M_AXI_WREADY, M_AXI_BVALID,
                M_AXI_BREADY, rn, wn, ar, aw, bn, dut.rd_state, dut.wr_state, memory.injection_count);
            #1;
            if (prior_re && !raccept) check(mem_rd_err, "read error sticky until accepted START/reset");
            if (prior_we && !waccept) check(mem_wr_err, "write error sticky until accepted START/reset");
            if (raccept) check(!mem_rd_err, "read error clears on accepting START edge, after NBA");
            if (waccept) check(!mem_wr_err, "write error clears on accepting START edge, after NBA");
            if (rbad_edge) check(mem_rd_err, "bad R response sets error on acceptance edge");
            if (bbad_edge) check(mem_wr_err, "bad B response sets error on acceptance edge");
            prior_re = mem_rd_err; prior_we = mem_wr_err;
            if (rmon && rstarted) begin
                if (!rexpect) check(!mem_rd_err, "clean read error not contaminated");
                if (mem_rd_err && re_first == 0) begin re_first = cycle; re_waits = rwait_run; end
                if (rprebusy && !mem_rd_busy) begin rdone = 1; rf = cycle; end
            end
            if (wmon && wstarted) begin
                if (!wexpect) check(!mem_wr_err, "clean write error not contaminated");
                if (mem_wr_err && we_first == 0) begin we_first = cycle; we_waits = wwait_run; end
                if (wprebusy && !mem_wr_busy) begin wdone = 1; wf = cycle; end
            end
        end
    end

    task automatic reset_pair;
        reg [1:0] busy_before, err_before;
        integer j;
        begin
            @(negedge clk);
            busy_before = {mem_rd_busy,mem_wr_busy}; err_before = {mem_rd_err,mem_wr_err};
            resetn = 0; mem_rd_start = 0; mem_wr_start = 0; rmon = 0; wmon = 0;
            #1;
            check({M_AXI_ARVALID,M_AXI_AWVALID,M_AXI_WVALID} === 3'b000, "reset VALID gates before rising edge");
            // Ignore unknown power-up values; active-transfer calls prove sync state reset.
            if (!$isunknown({busy_before,err_before}))
                check({mem_rd_busy,mem_wr_busy,mem_rd_err,mem_wr_err} === {busy_before,err_before},
                    "busy/error state unchanged before reset sampling edge");
            for (j=0; j<2; j=j+1) begin
                @(posedge clk); #2;
                check({mem_rd_busy,mem_wr_busy,mem_rd_err,mem_wr_err} === 4'b0000 &&
                    dut.rd_state == 0 && dut.wr_state == 0, "synchronous reset returns both FSMs to IDLE");
                check({M_AXI_ARVALID,M_AXI_AWVALID,M_AXI_WVALID} === 3'b000, "VALID zero through reset");
            end
            @(negedge clk); resetn = 1;
            repeat (2) begin @(posedge clk); #2; end
            $display("PASS: %s reset_pair sampled_edges=2 busy_before=%b err_before=%b busy_after=00 err_after=00 C12_violations=%0d",
                label, busy_before, err_before, memory.violation_count);
        end
    endtask

    task automatic begin_case(input string name);
        begin
            label = name; enabled = 1; invalid_active = 0;
            memory.ar_ready_mode = 0; memory.aw_ready_mode = 0; memory.w_ready_mode = 0;
            memory.r_gap_cycles = 0; memory.b_delay_cycles = 0; memory.ddr_latency_cycles = 0;
            memory.check_outstanding = 1; mem_rd_ready = 1;
            reset_pair;
            rn=0; wn=0; ar=0; aw=0; bn=0; ri_words=0; wi_words=0;
            inj_before = memory.injection_count;
            $display("CASE: WD=%0d %s expected_checker_codes=NONE; slave injections counted separately", WD, label);
        end
    endtask

    task automatic end_case(input integer injections);
        begin
            memory.check_quiescent;
            check(memory.violation_count == 0 && memory.expected_violation_count == 0,
                  "all M00 checker violations remain fatal");
            check(memory.injection_count-inj_before == injections, "exact requested injection count");
            cases = cases+1;
            $display("PASS: %s END injections=%0d expected_checker_codes=NONE master_violations=0 quiescent=1",
                label, memory.injection_count-inj_before);
        end
    endtask

    task automatic prepare_r(input reg [31:0] addr, input integer bytes,
        input reg [31:0] seed, input integer kind, target, input bit fill, expected_error);
        begin
            check(!mem_rd_busy, "prepare read only while idle");
            rbase=addr; rbytes=bytes; rseed=seed; rkind=kind; rtarget=target; rexpect=expected_error;
            rn=0; ar=0; ri_words=0; rs=0; rf=0; rbusy=0; re_high=0;
            re_first=0; rbad=0; rbad_first=0; rbad_burst=0; rwait_run=0; re_waits=0;
            rstarted=0; rdone=0; rarmed=0; rmon=1;
            if (fill) memory.mem_fill(addr,bytes,seed);
            mem_rd_addr=addr; mem_rd_bytes=bytes;
        end
    endtask

    task automatic prepare_w(input reg [31:0] addr, input integer bytes,
        input reg [31:0] seed, input integer kind, target, input bit expected_error);
        begin
            check(!mem_wr_busy, "prepare write only while idle");
            wbase=addr; wbytes=bytes; wseed=seed; wkind=kind; wtarget=target; wexpect=expected_error;
            wn=0; aw=0; bn=0; wi_words=0; ws=0; wf=0; wbusy=0; we_high=0;
            we_first=0; bbad=0; bbad_first=0; bbad_burst=0; wwait_run=0; we_waits=0;
            wstarted=0; wdone=0; warmed=0; wmon=1;
            mem_wr_addr=addr; mem_wr_bytes=bytes;
        end
    endtask

    task automatic issue(input bit rd, wr);
        bit old_re, old_we;
        begin
            @(negedge clk); old_re=mem_rd_err; old_we=mem_wr_err;
            mem_rd_start=rd; mem_wr_start=wr;
            #1;
            check(mem_rd_err === old_re && mem_wr_err === old_we, "START level alone does not clear sticky error");
            @(posedge clk); #2;
            if (rd) check(mem_rd_busy && !mem_rd_err, "START sample sets read busy and clears read error");
            if (wr) check(mem_wr_busy && !mem_wr_err, "START sample sets write busy and clears write error");
            $display("PASS: %s START rd=%b wr=%b old_err=%b%b clear_edge=%0d err_after=%b%b busy_after=%b%b",
                label, rd, wr, old_re, old_we, cycle, mem_rd_err, mem_wr_err, mem_rd_busy, mem_wr_busy);
            @(negedge clk); mem_rd_start=0; mem_wr_start=0;
        end
    endtask

    task automatic wait_done(input bit rd, wr);
        integer deadline;
        begin
            deadline=cycle+10000;
            while ((rd && !rdone) || (wr && !wdone)) begin
                @(posedge clk); #2; check(cycle<deadline, "bounded normal completion");
            end
            @(negedge clk);
            if (rd) rmon=0;
            if (wr) wmon=0;
        end
    endtask

    task automatic audit_r(input bit error_expected);
        integer j;
        begin
            check(!mem_rd_busy && mem_rd_err === error_expected, "read final busy/error");
            check(rn == rbytes/8 && ri_words == rn, "read drains complete command range");
            for (j=0;j<rn;j=j+1)
                check(rcollected[j] === pattern(rbase+8*j,rseed), $sformatf("full read data word %0d",j));
            $display("PASS: %s READ beats=%0d AR=%0d busy_cycles=%0d err_high_sample_cycles=%0d first_err_edge=%0d bad_beats=%0d bad_burst=%0d first_bad_word_1based=%0d remaining_after_first_bad=%0d finish_edge=%0d",
                label,rn,ar,rbusy,re_high,re_first,rbad,rbad_burst,rbad_first,
                rbad_first==0 ? 0 : rn-rbad_first,rf);
        end
    endtask

    task automatic audit_w(input bit error_expected);
        integer j, mismatches;
        begin
            check(!mem_wr_busy && mem_wr_err === error_expected, "write final busy/error");
            check(wn == wbytes/8 && wi_words == wn && bn == aw, "write drains all W and B bursts");
            for (j=0;j<wn;j=j+1)
                check(wcollected[j] === pattern(wbase+8*j,wseed), $sformatf("full write data word %0d",j));
            memory.mem_compare(wbase,wbytes,wseed,mismatches);
            check(mismatches==0, "complete write contents despite response error");
            $display("PASS: %s WRITE beats=%0d AW=%0d B=%0d busy_cycles=%0d err_high_sample_cycles=%0d first_err_edge=%0d bad_B=%0d bad_burst=%0d words_at_bad_B=%0d remaining_after_bad_B=%0d finish_edge=%0d mem_mismatches=%0d",
                label,wn,aw,bn,wbusy,we_high,we_first,bbad,bbad_burst,bbad_first,
                bbad_first==0 ? 0 : wn-bbad_first,wf,mismatches);
        end
    endtask

    task automatic read_back_write;
        begin
            prepare_r(wbase,wbytes,wseed,0,0,0,0);
            issue(1,0); wait_done(1,0); audit_r(0);
            $display("PASS: %s write_readback_words=%0d mismatches=0",label,rn);
        end
    endtask

    task automatic sticky_idle(input bit rd);
        integer j;
        begin
            for (j=0;j<5;j=j+1) begin
                @(posedge clk); #2;
                check(rd ? mem_rd_err : mem_wr_err, "sticky error during idle without START");
            end
            $display("PASS: %s %s sticky_idle_cycles=5 err=1 last_edge=%0d",label,rd?"read":"write",cycle);
        end
    endtask

    task automatic read_error(input integer kind);
        begin
            if (kind==1) begin_case("E1_E3_RRESP_middle");
            else begin_case("E2_E3_RID_middle");
            prepare_r(32'h18000000+kind*4096,384,'h301,kind,2,1,1);
            issue(1,0); wait_done(1,0); audit_r(1);
            check(ar==3 && rbad_burst==2 && rbad==(kind==1 ? 1 : 16), "targeted middle read burst fault");
            sticky_idle(1);
            prepare_r(32'h18003000+kind*4096,8,'h302,0,0,1,0);
            issue(1,0); wait_done(1,0); audit_r(0);
            repeat(5) begin @(posedge clk); #2; check(!mem_rd_err,"clean read leaves error zero"); end
            end_case(1);
        end
    endtask

    task automatic write_error(input integer kind);
        begin
            if (kind==1) begin_case("E4_BRESP_middle");
            else begin_case("E4_BID_middle");
            prepare_w(32'h18100000+kind*4096,384,'h401,kind,2,1);
            issue(0,1); wait_done(0,1); audit_w(1);
            check(aw==3 && bbad_burst==2 && bbad==1, "targeted middle B response");
            read_back_write;
            sticky_idle(0);
            prepare_w(32'h18103000+kind*4096,8,'h402,0,0,0);
            issue(0,1); wait_done(0,1); audit_w(0);
            repeat(5) begin @(posedge clk); #2; check(!mem_wr_err,"clean write leaves error zero"); end
            end_case(1);
        end
    endtask

    task automatic invalid_case(input string name, input reg [31:0] addr, input integer bytes);
        begin
            begin_case(name);
            invalid_active=1;
            prepare_r(addr,bytes,0,0,0,0,1); prepare_w(addr,bytes,0,0,0,1);
            issue(1,1); wait_done(1,1);
            check(mem_rd_err && mem_wr_err && !mem_rd_busy && !mem_wr_busy,"invalid command reports both errors then idle");
            check(ar==0 && aw==0 && rn==0 && wn==0 && bn==0,"invalid command emits no AXI transaction");
            check(rbusy==1 && wbusy==1 && re_first==rs+1 && we_first==ws+1,"invalid command detected in PLAN on following edge");
            repeat(5) begin
                @(posedge clk); #2;
                check(!M_AXI_ARVALID && !M_AXI_AWVALID && !M_AXI_WVALID && mem_rd_err && mem_wr_err,
                      "invalid command remains idle with sticky error and no AXI VALID");
            end
            $display("PASS: %s addr=%08h bytes=%0d AR=0 AW=0 W=0 B=0 rd_busy_cycles=%0d wr_busy_cycles=%0d err_edge=%0d start_edge=%0d sticky_idle_cycles=5",
                label,addr,bytes,rbusy,wbusy,re_first,rs);
            end_case(0);
        end
    endtask

    task automatic simultaneous(input integer mode);
        integer rfinish, wfinish;
        begin
            if (mode==0) begin_case("E8_clean_W_finishes_first");
            else if (mode==1) begin_case("E8_R_error_R_finishes_first");
            else begin_case("E8_W_error_W_finishes_first");
            if (mode==1) memory.b_delay_cycles=80;
            if (mode==2) memory.r_gap_cycles=4;
            prepare_r(32'h18300000,384,'h601,mode==1 ? 1 : 0,2,1,mode==1);
            prepare_w(32'h18310000+mode*4096,mode==2 ? 384 : 24,'h602,mode==2 ? 1 : 0,2,mode==2);
            issue(1,1); wait_done(1,1);
            audit_r(mode==1); audit_w(mode==2);
            check(rs==ws,"both commands accepted on same edge");
            if (mode==1) check(rf<wf,"read with error finishes while clean write remains active");
            else check(wf<rf,"write finishes while read remains active");
            rfinish=rf; wfinish=wf;
            $display("PASS: %s simultaneous_start=%0d read_finish=%0d write_finish=%0d read_err=%b write_err=%b clean_side_error_contamination=0",
                label,rs,rfinish,wfinish,mem_rd_err,mem_wr_err);
            read_back_write;
            end_case(mode==0 ? 0 : 1);
        end
    endtask

    task automatic watchdog_case(input integer mode);
        integer j, first_wait, original_count;
        reg [31:0] held_addr;
        reg [63:0] held_data;
        begin
            case (mode)
                0: begin_case("E7_AR_stall");
                1: begin_case("E7_R_stall");
                2: begin_case("E7_AW_W_stall");
                3: begin_case("E7_B_stall");
            endcase
            check(WD==8,"watchdog fixture parameter really enabled");
            if (mode==0) begin memory.ar_ready_mode=1; memory.ar_gap_cycles=127; end
            if (mode==1) memory.ddr_latency_cycles=64;
            if (mode==2) begin
                memory.aw_ready_mode=1; memory.aw_gap_cycles=127;
                memory.w_ready_mode=1; memory.w_gap_cycles=127;
            end
            if (mode==3) memory.b_delay_cycles=64;
            // Allow registered READY controls to reflect the requested stall.
            repeat(2) begin @(posedge clk); #2; end
            if (mode<2) prepare_r(32'h18400000,128,'h701,0,0,1,1);
            else prepare_w(32'h18410000+mode*4096,128,'h702,0,0,1);
            issue(mode<2,mode>=2);
            if (mode==0) wait(M_AXI_ARVALID);
            if (mode==1) wait(ar==1);
            if (mode==2) wait(M_AXI_AWVALID && M_AXI_WVALID);
            if (mode==3) wait(M_AXI_BREADY);
            @(negedge clk); first_wait=cycle;
            held_addr=mode<2 ? M_AXI_ARADDR : M_AXI_AWADDR; held_data=M_AXI_WDATA;
            for (j=0;j<24;j=j+1) begin
                @(posedge clk); #2;
                if (mode<2) check(mem_rd_busy,"watchdog never cancels read busy");
                else check(mem_wr_busy,"watchdog never cancels write busy");
                if (mode==0) check(M_AXI_ARVALID && M_AXI_ARADDR===held_addr && ar==0 && rn==0,
                    "AR VALID/payload persist after timeout until acceptance");
                if (mode==1) check(ar==1 && rn==0 && M_AXI_RREADY,"accepted read outstanding after timeout");
                if (mode==2) check(M_AXI_AWVALID && M_AXI_WVALID && M_AXI_AWADDR===held_addr &&
                    M_AXI_WDATA===held_data && aw==0 && wn==0,"AW/W VALID and payload never withdrawn after timeout");
                if (mode==3) check(aw==1 && wn==16 && bn==0 && M_AXI_BREADY,"accepted write waits for B after timeout");
            end
            check(mode<2 ? mem_rd_err : mem_wr_err,"watchdog timeout actually asserted error");
            check(mode<2 ? re_waits==WD : we_waits==WD,"timeout observed on eighth consecutive waiting edge");
            $display("PASS: %s WATCHDOG=%0d observed_waits_at_error=%0d first_err_edge=%0d hold_observed=24 busy_preserved=1 valid_or_outstanding_preserved=1 AR=%0d AW=%0d R=%0d W=%0d B=%0d",
                label,WD,mode<2?re_waits:we_waits,mode<2?re_first:we_first,ar,aw,rn,wn,bn);
            @(negedge clk);
            memory.ar_ready_mode=0; memory.aw_ready_mode=0; memory.w_ready_mode=0;
            // R/B latency already latched/measured; let the scheduled response arrive.
            wait_done(mode<2,mode>=2);
            if (mode<2) audit_r(1); else audit_w(1);
            // A new error-free command clears the watchdog error too.
            memory.ddr_latency_cycles=0; memory.b_delay_cycles=0;
            if (mode<2) begin
                prepare_r(32'h18430000,8,'h703,0,0,1,0); issue(1,0); wait_done(1,0); audit_r(0);
            end else begin
                read_back_write;
                prepare_w(32'h18440000+mode*4096,8,'h704,0,0,0); issue(0,1); wait_done(0,1); audit_w(0);
            end
            end_case(0);
        end
    endtask

    task automatic transfer_reset(input bit rd);
        integer old_beats, j;
        begin
            if (rd) begin_case("E9_read_mid_reset");
            else begin_case("E9_write_mid_reset");
            if (rd) prepare_r(32'h18500000,128,'h801,0,0,1,0);
            else prepare_w(32'h18510000,128,'h802,0,0,0);
            issue(rd,!rd);
            while (rd ? rn<5 : wn<5) begin @(posedge clk); #2; end
            old_beats=rd?rn:wn;
            check(old_beats==5 && (rd?mem_rd_busy:mem_wr_busy),"reset injected during partial active burst");
            // No quiescent declaration for the intentionally aborted transaction.
            reset_pair;
            if (!rd) begin
                for(j=0;j<5;j=j+1) check(memory.mem_word(32'h18510000+j*8)===pattern(32'h18510000+j*8,'h802),
                    "reset does not roll back already written data");
            end
            $display("PASS: %s aborted_beats=%0d requested_beats=16 reset_edges=2 busy=00 err=00 VALID=000 partial_write_rollback=none",label,old_beats);
            if (rd) begin
                prepare_r(32'h18520000,128,'h803,0,0,1,0); issue(1,0); wait_done(1,0); audit_r(0);
            end else begin
                prepare_w(32'h18530000,128,'h804,0,0,0); issue(0,1); wait_done(0,1); audit_w(0); read_back_write;
            end
            end_case(0);
        end
    endtask

    task automatic rlast_fault(input integer mode);
        integer j, frozen_beats, fault_edge;
        begin
            if (mode==1) begin_case("E5_E9_early_RLAST");
            else begin_case("E5_E9_missing_RLAST");
            fault_mode=mode;
            prepare_r(32'h18600000+mode*4096,128,'h901,3,1,1,1);
            issue(1,0);
            while (dut.rd_state!=3'd4) begin
                @(posedge clk); #2; check(cycle-rs<100,"RD_FAULT entry deadline");
            end
            fault_edge=cycle; frozen_beats=rn;
            check(rn==(mode==1?15:16) && mem_rd_busy && mem_rd_err,"RLAST mismatch enters RD_FAULT with error");
            for(j=0;j<2000;j=j+1) begin
                @(negedge clk);
                // START in RD_FAULT is ignored; toggling consumer READY cannot recover it.
                mem_rd_start=(j==10); mem_rd_ready=(j%2)==0;
                @(posedge clk); #2;
                check(dut.rd_state==3'd4 && mem_rd_busy && mem_rd_err,"RD_FAULT self-loop persists");
                check(!M_AXI_ARVALID && !M_AXI_RREADY && rn==frozen_beats && ar==1,
                      "RD_FAULT issues no new AR and accepts no remaining R");
            end
            @(negedge clk); mem_rd_start=0; mem_rd_ready=1;
            for(j=0;j<rn;j=j+1) check(rcollected[j]===pattern(rbase+8*j,rseed),"data before malformed RLAST matches");
            check(memory.rlast_injected>=1 && memory.injection_count-inj_before==1,"one malformed RLAST injection observed");
            $display("PASS: %s mode=%0d entry_edge=%0d state=%0d busy_hold_cycles=2000 received_beats=%0d pending_words=%0d err_high_sample_cycles=%0d busy_samples=%0d START_while_fault=ignored READY_toggle=no_effect master_violations=%0d quiescent=SKIPPED",
                label,mode,fault_edge,dut.rd_state,rn,16-rn,re_high,rbusy,memory.violation_count);
            // Intentional nontermination: NEVER call check_quiescent here.
            reset_pair;
            check(memory.violation_count==0,"C12 remains zero on fault recovery reset");
            cases=cases+1;
            $display("PASS: %s recovery=coordinated_reset state=IDLE err=0 busy=0 expected_checker_codes=NONE injections=1",label);
            // Separate normally terminating recovery command after the fault case.
            if (mode==1) label="E5_recovery_after_early";
            else label="E5_recovery_after_missing";
            inj_before=memory.injection_count;
            prepare_r(32'h18610000+mode*4096,128,'h902,0,0,1,0);
            issue(1,0); wait_done(1,0); audit_r(0); end_case(0);
        end
    endtask

    initial begin
        trace=$fopen($sformatf("err_cycles_wd%0d.csv",WD),"w");
        check(trace!=0,"open cycle trace");
        $fdisplay(trace,"case,cycle,resetn,rd_start,wr_start,rd_busy,wr_busy,rd_err,wr_err,arvalid,arready,rvalid,rready,awvalid,awready,wvalid,wready,bvalid,bready,R,W,AR,AW,B,rd_state,wr_state,injections");
    end
endmodule

module tb_m00_err;
    m00_err_fixture #(.WD(0)) normal();
    m00_err_fixture #(.WD(8)) watchdog();
    initial begin #2000000; $fatal(1,"FAIL: T-02d global deadline"); end
    initial begin
        normal.read_error(1); normal.read_error(2);
        normal.write_error(1); normal.write_error(2);
        normal.invalid_case("E6_zero_length",32'h18200000,0);
        normal.invalid_case("E6_unaligned_address",32'h18200001,8);
        normal.invalid_case("E6_unaligned_length",32'h18200000,10);
        normal.invalid_case("E6_address_overflow",32'hfffffff8,16);
        normal.begin_case("E6_end_exactly_2pow32_is_valid");
        normal.prepare_r(32'hfffffff8,8,'h501,0,0,1,0);
        normal.prepare_w(32'hfffffff8,8,'h501,0,0,0);
        normal.issue(1,1); normal.wait_done(1,1); normal.audit_r(0); normal.audit_w(0); normal.end_case(0);
        normal.simultaneous(0); normal.simultaneous(1); normal.simultaneous(2);
        watchdog.watchdog_case(0); watchdog.watchdog_case(1);
        watchdog.watchdog_case(2); watchdog.watchdog_case(3);
        normal.transfer_reset(1); normal.transfer_reset(0);
        // Nonterminating cases are isolated and placed last.
        normal.rlast_fault(1); normal.rlast_fault(2);
        normal.memory.check_quiescent; watchdog.memory.check_quiescent;
        normal.check(normal.memory.violation_count==0 && watchdog.memory.violation_count==0,"all fixtures zero master violations");
        $display("PASS: T-02d E1-E9 ALL CHECKS cases=%0d normal_injections=%0d watchdog_injections=%0d master_violations=0 expected_checker_violations=0 C12=0 RD_FAULT_hold=2000_each reset_recovery=PASS",
            normal.cases+watchdog.cases,normal.memory.injection_count,watchdog.memory.injection_count);
        $fclose(normal.trace); $fclose(watchdog.trace);
        $finish;
    end
endmodule
