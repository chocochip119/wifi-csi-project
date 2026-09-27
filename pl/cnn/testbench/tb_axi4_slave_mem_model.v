`timescale 1ns / 1ps

// T-02a: an independent procedural AXI master; no production RTL is used.
module tb_axi4_slave_mem_model;
    reg clk = 0, resetn = 1;
    always #5 clk = ~clk;
    integer cycle = 0;
    always @(posedge clk) cycle <= cycle + 1;
    reg awid = 0, arid = 0;
    reg [31:0] awaddr = 0, araddr = 0;
    reg [7:0] awlen = 0, arlen = 0;
    reg [2:0] awsize = 3, arsize = 3;
    reg [1:0] awburst = 1, arburst = 1;
    reg awvalid = 0, arvalid = 0, wvalid = 0, wlast = 0;
    reg [63:0] wdata = 0;
    reg [7:0] wstrb = 8'hff;
    reg bready = 0, rready = 0;
    reg allow_reset_violation = 0;
    // Reproduce R-01 combinational VALID gating without instantiating M00.
    wire bus_awvalid = awvalid && (resetn || allow_reset_violation);
    wire bus_arvalid = arvalid && (resetn || allow_reset_violation);
    wire bus_wvalid = wvalid && (resetn || allow_reset_violation);
    wire awready, arready, wready, bid, bvalid, rid, rlast, rvalid;
    wire [1:0] bresp, rresp;
    wire [63:0] rdata;
    axi4_slave_mem_model dut (
        .clk(clk), .resetn(resetn),
        .M_AXI_AWID(awid), .M_AXI_AWADDR(awaddr), .M_AXI_AWLEN(awlen),
        .M_AXI_AWSIZE(awsize), .M_AXI_AWBURST(awburst), .M_AXI_AWLOCK(1'b0),
        .M_AXI_AWCACHE(4'b0011), .M_AXI_AWPROT(3'b0), .M_AXI_AWQOS(4'b0),
        .M_AXI_AWVALID(bus_awvalid), .M_AXI_AWREADY(awready),
        .M_AXI_WDATA(wdata), .M_AXI_WSTRB(wstrb), .M_AXI_WLAST(wlast),
        .M_AXI_WVALID(bus_wvalid), .M_AXI_WREADY(wready),
        .M_AXI_BID(bid), .M_AXI_BRESP(bresp), .M_AXI_BVALID(bvalid), .M_AXI_BREADY(bready),
        .M_AXI_ARID(arid), .M_AXI_ARADDR(araddr), .M_AXI_ARLEN(arlen),
        .M_AXI_ARSIZE(arsize), .M_AXI_ARBURST(arburst), .M_AXI_ARLOCK(1'b0),
        .M_AXI_ARCACHE(4'b0011), .M_AXI_ARPROT(3'b0), .M_AXI_ARQOS(4'b0),
        .M_AXI_ARVALID(bus_arvalid), .M_AXI_ARREADY(arready),
        .M_AXI_RID(rid), .M_AXI_RDATA(rdata), .M_AXI_RRESP(rresp),
        .M_AXI_RLAST(rlast), .M_AXI_RVALID(rvalid), .M_AXI_RREADY(rready)
    );

    task automatic check(input bit condition, input string message);
        if (!condition) begin
            $display("FAIL: %s at %0t", message, $time);
            $fatal(1, "T-02a self-test failed");
        end
    endtask

    // Independent expected-data formula, never calls the model pattern helper.
    function automatic [63:0] expected_word(input reg [31:0] addr, seed);
        expected_word[63:32] = seed ^ 32'hA5C39E71;
        expected_word[31:0] = addr ^ seed;
    endfunction

    task automatic defaults;
        begin
            dut.ar_ready_mode = 0; dut.aw_ready_mode = 0; dut.w_ready_mode = 0;
            dut.ar_gap_cycles = 0; dut.aw_gap_cycles = 0; dut.w_gap_cycles = 0;
            dut.ddr_latency_cycles = 0; dut.r_gap_cycles = 0; dut.b_delay_cycles = 0;
            dut.check_outstanding = 1; dut.write_timeout_cycles = 0;
        end
    endtask

    task automatic reset_model;
        begin
            @(negedge clk);
            arvalid = 0; awvalid = 0; wvalid = 0; rready = 0; bready = 0;
            arsize = 3; awsize = 3; arburst = 1; awburst = 1; arid = 0; awid = 0;
            wstrb = 8'hff; resetn = 0;
            repeat (2) begin @(posedge clk); #1; end
            @(negedge clk); resetn = 1;
            @(posedge clk); #1;
            @(negedge clk);
        end
    endtask

    integer ar_cycle, aw_cycle, last_w_cycle, b_cycle, ar_stalls;
    integer r_cycles [0:15];
    integer w_stalls, w_samples;
    reg [63:0] w_trace;
    task automatic send_ar(input reg [31:0] addr, input integer beats);
        begin
            @(negedge clk); araddr = addr; arlen = beats-1; arvalid = 1; ar_stalls = 0;
            @(posedge clk);
            while (!arready) begin ar_stalls = ar_stalls + 1; @(posedge clk); end
            ar_cycle = cycle;
            @(negedge clk); arvalid = 0;
        end
    endtask

    task automatic send_aw(input reg [31:0] addr, input integer beats);
        begin
            @(negedge clk); awaddr = addr; awlen = beats-1; awvalid = 1;
            @(posedge clk);
            while (!awready) @(posedge clk);
            aw_cycle = cycle;
            @(negedge clk); awvalid = 0;
        end
    endtask

    task automatic send_w(input reg [31:0] addr, input integer beats, input reg [31:0] seed);
        integer j;
        begin
            w_trace = 0; w_samples = 0; w_stalls = 0;
            @(negedge clk);
            for (j = 0; j < beats; j = j + 1) begin
                wdata = expected_word(addr+j*8, seed); wlast = j == beats-1; wvalid = 1;
                @(posedge clk);
                while (!wready) begin
                    w_trace = {w_trace[62:0], 1'b0}; w_samples = w_samples + 1;
                    w_stalls = w_stalls + 1;
                    @(posedge clk);
                end
                w_trace = {w_trace[62:0], 1'b1}; w_samples = w_samples + 1;
                last_w_cycle = cycle;
                @(negedge clk); wvalid = 0;
            end
        end
    endtask

    task automatic get_b(input reg [1:0] expected_resp, input bit expected_id);
        begin
            bready = 1;
            @(posedge clk);
            while (!bvalid) @(posedge clk);
            b_cycle = cycle;
            check(bresp === expected_resp && bid === expected_id, "B response/ID");
            check(b_cycle > aw_cycle && b_cycle > last_w_cycle, "B only after AW AND WLAST");
            @(negedge clk); bready = 0;
        end
    endtask

    task automatic get_r(input reg [31:0] addr, input integer beats,
        input reg [31:0] seed, input bit unwritten,
        input reg [1:0] fault_resp, input integer fault_beat,
        input bit fault_id, input integer last_mode);
        integer j;
        bit expected_last;
        reg [63:0] expected_data;
        begin
            rready = 1;
            for (j = 0; j < beats; j = j + 1) begin
                @(posedge clk);
                while (!rvalid) @(posedge clk);
                r_cycles[j] = cycle;
                expected_data = unwritten ? 64'hDEAD_BEEF_BAD0_0001 : expected_word(addr+j*8, seed);
                check(rdata === expected_data, $sformatf("read address %08h beat %0d data", addr, j));
                check(rresp === (j == fault_beat ? fault_resp : 2'b00), "RRESP selected beat only");
                check(rid === fault_id, "RID matches expected injection");
                expected_last = j == beats-1;
                if (last_mode == 1) expected_last = j == beats-2;
                if (last_mode == 2) expected_last = 0;
                check(rlast === expected_last, "RLAST position");
            end
            @(negedge clk); rready = 0;
        end
    endtask

    task automatic read_normal(input reg [31:0] addr, input integer beats, input reg [31:0] seed);
        begin send_ar(addr, beats); get_r(addr, beats, seed, 0, 0, 0, 0, 0); end
    endtask

    task automatic write_normal(input reg [31:0] addr, input integer beats, input reg [31:0] seed);
        begin
            fork send_aw(addr, beats); send_w(addr, beats, seed); join
            get_b(0, 0);
        end
    endtask

    // Independent slave-output monitor: R/B must remain stable under stalls.
    bit r_held = 0, b_held = 0;
    reg [67:0] saved_r;
    reg [2:0] saved_b;
    integer r_hold_checks = 0, b_hold_checks = 0;
    always @(posedge clk) begin
        if (!resetn) begin r_held = 0; b_held = 0; end
        else begin
            if (r_held) begin
                check(rvalid && {rid,rdata,rresp,rlast} === saved_r, "slave R stable while RREADY=0");
                r_hold_checks = r_hold_checks + 1;
            end
            if (b_held) begin
                check(bvalid && {bid,bresp} === saved_b, "slave B stable while BREADY=0");
                b_hold_checks = b_hold_checks + 1;
            end
            r_held = rvalid && !rready; saved_r = {rid,rdata,rresp,rlast};
            b_held = bvalid && !bready; saved_b = {bid,bresp};
        end
    end

    integer before_violation, negative_tests = 0;
    task automatic arm_negative(input integer code);
        begin
            defaults; reset_model;
            before_violation = dut.violation_count;
            dut.expect_violation(code);
        end
    endtask
    task automatic check_negative(input integer code, input string name);
        begin
            #1;
            check(dut.violation_count == before_violation+1 && dut.expected_code == 0 &&
                  dut.last_violation_code == code, "exactly one matching violation and auto-disarm");
            negative_tests = negative_tests + 1;
            $display("PASS: %s -> C%0d detected exactly once; delta=1", name, code);
        end
    endtask

    integer mismatches, j, baseline, delayed, base_gap, base_b, ar_wait;
    integer random_stalls, random_samples;
    reg [63:0] random_trace;
    initial begin
        #200000;
        $fatal(1, "FAIL: T-02a watchdog timeout");
    end
    initial begin
        defaults; reset_model;
        // Optional fatal-mode probes are separate runs; normal run stays positive.
        if ($test$plusargs("FATAL_UNEXPECTED")) begin
            arsize = 2; send_ar(32'h1000, 1);
            $fatal(1, "FAIL: unexpected C4 did not terminate");
        end
        if ($test$plusargs("FATAL_ONESHOT")) begin
            dut.expect_violation(4); arsize = 2; send_ar(32'h1000, 1);
            get_r(32'h1000, 1, 0, 1, 0, 0, 0, 0);
            send_ar(32'h1008, 1);
            $fatal(1, "FAIL: one-shot expectation suppressed a second C4");
        end

        write_normal(32'h1000, 1, 32'h11); read_normal(32'h1000, 1, 32'h11);
        $display("PASS: A1 single-beat write/read data match");
        write_normal(32'h2000, 16, 32'h22); read_normal(32'h2000, 16, 32'h22);
        $display("PASS: A2 16-beat write/read all words match");
        write_normal(32'h3000, 4, 32'h33); write_normal(32'h4000, 4, 32'h44);
        read_normal(32'h3000, 4, 32'h33); read_normal(32'h4000, 4, 32'h44);
        $display("PASS: A3 consecutive bursts preserve distinct addresses and data");
        dut.mem_fill(32'h1e020000+399152, 320, 32'h55);
        read_normal(32'h1e020000+399152, 16, 32'h55);
        read_normal(32'h1e020000+399152+128, 16, 32'h55);
        read_normal(32'h1e020000+399152+256, 8, 32'h55);
        dut.mem_compare(32'h1e020000+399152, 320, 32'h55, mismatches);
        check(mismatches == 0, "mem_compare full 320-byte filled range");
        dut.mem_compare(32'h1e020000+399152, 8, 32'h56, mismatches);
        check(mismatches == 1, "mem_compare must detect wrong pattern seed");
        $display("PASS: A4 sparse mem_fill/read 40 words; compare=0; wrong-seed compare=1");
        send_ar(32'h70000000, 1); get_r(32'h70000000, 1, 0, 1, 0, 0, 0, 0);
        check(dut.mem_word(32'h70000000) !== 64'b0, "unwritten marker is nonzero");
        $display("PASS: A5 unwritten address returns DEAD_BEEF_BAD0_0001");
        send_w(32'h5000, 4, 32'h66);
        repeat (3) begin @(posedge clk); #1; check(!bvalid, "no B before AW"); end
        check(dut.mem_word(32'h5000) === 64'hDEAD_BEEF_BAD0_0001, "W before AW stays buffered");
        send_aw(32'h5000, 4); get_b(0, 0); read_normal(32'h5000, 4, 32'h66);
        $display("PASS: A6 all 4 W beats before AW; no early B; buffered data read back");
        send_aw(32'h5100, 2);
        repeat (3) begin @(posedge clk); #1; check(!bvalid, "no B before WLAST"); end
        send_w(32'h5100, 2, 32'h66); get_b(0, 0); read_normal(32'h5100, 2, 32'h66);
        $display("PASS: A6-extra AW first, no B while waiting for WLAST, then correct response/data");

        // Independent directions and R/B stalls (also exercise the model itself).
        fork read_normal(32'h2000, 16, 32'h22); write_normal(32'h6000, 16, 32'h77); join
        send_ar(32'h6000, 16);
        repeat (5) begin @(posedge clk); #1; end
        @(negedge clk); get_r(32'h6000, 16, 32'h77, 0, 0, 0, 0, 0);
        fork send_aw(32'h8000, 1); send_w(32'h8000, 1, 32'h88); join
        repeat (5) begin @(posedge clk); #1; end
        @(negedge clk); get_b(0, 0);
        check(r_hold_checks >= 4 && b_hold_checks >= 4, "response stall monitor actually exercised");
        $display("PASS: A-extra independent read/write; stable stalled R checks=%0d B checks=%0d", r_hold_checks, b_hold_checks);

        defaults; reset_model; read_normal(32'h2000, 4, 32'h22);
        baseline = r_cycles[0]-ar_cycle; base_gap = r_cycles[1]-r_cycles[0];
        check(baseline == 1 && base_gap == 1 && ar_stalls == 0, "zero-delay baseline gives consecutive beats");
        defaults; dut.ar_ready_mode = 1; dut.ar_gap_cycles = 7; reset_model;
        read_normal(32'h2000, 4, 32'h22); ar_wait = ar_stalls;
        check(ar_wait > 0, "periodic ARREADY produces measured wait");
        $display("PASS: B1 ARREADY gap=7 observed address stalls=%0d (baseline=0)", ar_wait);
        defaults; dut.r_gap_cycles = 3; reset_model; read_normal(32'h2000, 4, 32'h22);
        for (j = 1; j < 4; j = j+1) check(r_cycles[j]-r_cycles[j-1] == 4, "R gap=3 gives interval=4");
        $display("PASS: B2 R beat interval baseline=%0d configured-gap=3 observed=4 clocks", base_gap);
        defaults; reset_model; write_normal(32'h9000, 2, 32'h99); base_b = b_cycle-last_w_cycle;
        dut.b_delay_cycles = 4; write_normal(32'h9100, 2, 32'h99); delayed = b_cycle-last_w_cycle;
        check(base_b == 1 && delayed == 5, "B delay measured from WLAST acceptance");
        $display("PASS: B3 WLAST-to-B handshake baseline=%0d delay=4 observed=%0d clocks", base_b, delayed);
        send_w(32'h9200, 2, 32'h99);
        repeat (6) begin @(posedge clk); #1; check(!bvalid, "expired B delay still waits for AW"); end
        send_aw(32'h9200, 2); get_b(0, 0);
        check(b_cycle-aw_cycle == 1, "late AW must not restart WLAST-based delay");
        $display("PASS: B3-extra WLAST delay expired before AW; no early B, AW-to-B handshake=1 clock");
        defaults; dut.ddr_latency_cycles = 5; reset_model; read_normal(32'h2000, 4, 32'h22);
        delayed = r_cycles[0]-ar_cycle;
        check(delayed == baseline+5, "DDR delay adds exactly 5 clocks");
        $display("PASS: B4 AR-to-first-R handshake baseline=%0d latency=5 observed=%0d clocks", baseline, delayed);
        defaults; dut.w_ready_mode = 2; dut.w_seed = 32'h1234abcd; reset_model;
        write_normal(32'ha000, 16, 32'haa);
        random_trace = w_trace; random_stalls = w_stalls; random_samples = w_samples;
        defaults; dut.w_ready_mode = 2; dut.w_seed = 32'h1234abcd; reset_model;
        write_normal(32'ha000, 16, 32'haa);
        check(w_trace == random_trace && w_stalls == random_stalls && w_samples == random_samples && w_stalls > 0,
              "same-seed WREADY sampled trace and actual stall count reproduce");
        $display("PASS: B5 seed=1234ABCD repeated WREADY trace=%016h samples=%0d stalls=%0d", w_trace, w_samples, w_stalls);

        defaults; reset_model;
        dut.inject_rresp = 2; dut.inject_rresp_beat = 2;
        send_ar(32'h2000, 4); get_r(32'h2000, 4, 32'h22, 0, 2, 2, 0, 0);
        read_normal(32'h2000, 4, 32'h22);
        check(dut.inject_rresp == 0 && dut.rresp_injected == 1, "RRESP injection occurred once");
        $display("PASS: C1/C4 RRESP=SLVERR on beat 2 only; next burst OKAY; count=1");
        dut.inject_rid = 1;
        send_ar(32'h2000, 4); get_r(32'h2000, 4, 32'h22, 0, 0, 0, 1, 0);
        read_normal(32'h2000, 4, 32'h22);
        check(dut.inject_rid == 0 && dut.rid_injected == 1, "RID injection once per burst");
        $display("PASS: C2/C4 RID=1 in selected burst; next RID=0; count=1");
        dut.inject_bresp = 2;
        fork send_aw(32'hb000, 2); send_w(32'hb000, 2, 32'hbb); join
        get_b(2, 0); write_normal(32'hb100, 2, 32'hbb);
        check(dut.inject_bresp == 0 && dut.bresp_injected == 1, "BRESP injection once");
        $display("PASS: C2/C4 BRESP=SLVERR then next OKAY; count=1");
        dut.inject_bid = 1;
        fork send_aw(32'hb200, 2); send_w(32'hb200, 2, 32'hbb); join
        get_b(0, 1); write_normal(32'hb300, 2, 32'hbb);
        check(dut.inject_bid == 0 && dut.bid_injected == 1, "BID injection once");
        $display("PASS: C2/C4 BID=1 then next BID=0; count=1");
        dut.inject_rlast_mode = 1;
        send_ar(32'h2000, 4); get_r(32'h2000, 4, 32'h22, 0, 0, 0, 0, 1);
        read_normal(32'h2000, 4, 32'h22);
        check(dut.inject_rlast_mode == 0 && dut.rlast_injected == 1, "early RLAST once");
        $display("PASS: C3/C4 early RLAST at beat 2 instead of 3; next burst normal");
        dut.inject_rlast_mode = 2;
        send_ar(32'h2000, 4); get_r(32'h2000, 4, 32'h22, 0, 0, 0, 0, 2);
        read_normal(32'h2000, 4, 32'h22);
        check(dut.inject_rlast_mode == 0 && dut.rlast_injected == 2 && dut.injection_count == 6,
              "six requested faults actually driven exactly once each");
        $display("PASS: C3/C4/C5 missing RLAST then normal; counters RRESP/RID/BRESP/BID/RLAST=1/1/1/1/2 total=6");
        // Armed is not injected: reset cancels request before a burst exists.
        dut.inject_bid = 1; check(dut.injection_count == 6, "arming alone does not increment counter");
        reset_model; check(dut.injection_count == 6 && dut.inject_bid == 0, "reset cancels unused injection");

        dut.ar_ready_mode = 1; dut.ar_gap_cycles = 100;
        @(posedge clk); #1;
        @(negedge clk); arvalid = 1; araddr = 32'h1000; arlen = 0;
        @(posedge clk); #1; check(!arready, "reset gate test starts with a stalled VALID");
        @(negedge clk); resetn = 0;
        #1; check(!bus_arvalid && dut.violation_count == 0, "same-time reset gate is not a C12 violation");
        $display("PASS: C12-positive reset masks active master VALID after delta settling; violations=0");

        arm_negative(1); dut.ar_ready_mode = 1; dut.ar_gap_cycles = 100;
        @(posedge clk); #1;
        @(negedge clk); arvalid = 1; araddr = 32'h1000; arlen = 0;
        @(posedge clk); #1; check(!arready, "D1 actually stalled");
        @(negedge clk); araddr = 32'h1008;
        @(posedge clk); check_negative(1, "D1 ARADDR changes during AR stall");
        arm_negative(4); arsize = 2; send_ar(32'h1000, 1); check_negative(4, "D2 ARSIZE=2");
        arm_negative(5); send_ar(32'h1000, 17); check_negative(5, "D3 ARLEN=16 (17 beats)");
        arm_negative(7); send_ar(32'h1ff8, 2); check_negative(7, "D4 AR burst crosses 4 KiB");
        arm_negative(8); wstrb = 8'h0f; send_w(32'hc000, 1, 32'hcc); check_negative(8, "D5 WSTRB=0F");
        arm_negative(9); send_aw(32'hc000, 2); send_w(32'hc000, 1, 32'hcc);
        check_negative(9, "D6 WLAST one beat early");

        // Exercise the remaining checker clauses, not just implement them.
        arm_negative(2); dut.aw_ready_mode = 1; dut.aw_gap_cycles = 100;
        @(posedge clk); #1;
        @(negedge clk); awvalid = 1; awaddr = 32'h1000; awlen = 0;
        @(posedge clk); #1; check(!awready, "AW actually stalled");
        @(negedge clk); awvalid = 0;
        @(posedge clk); check_negative(2, "D-extra AWVALID drops during stall");
        arm_negative(3); dut.w_ready_mode = 1; dut.w_gap_cycles = 100;
        @(posedge clk); #1;
        @(negedge clk); wvalid = 1; wdata = 1; wlast = 1;
        @(posedge clk); #1; check(!wready, "W actually stalled");
        @(negedge clk); wdata = 2;
        @(posedge clk); check_negative(3, "D-extra WDATA changes during stall");
        arm_negative(6); send_aw(32'h1004, 1); check_negative(6, "D-extra misaligned AWADDR");
        arm_negative(10); send_aw(32'hc000, 2);
        dut.check_quiescent; check_negative(10, "D-extra declared end with missing W beats");
        arm_negative(10); send_w(32'hc000, 2, 32'hcc); send_aw(32'hc000, 1);
        check_negative(10, "D-extra buffered W count exceeds AWLEN+1");
        arm_negative(11); send_ar(32'h1000, 1);
        @(negedge clk); araddr = 32'h1008; arvalid = 1;
        @(posedge clk); check_negative(11, "D-extra second AR before first R completion");
        arm_negative(12);
        allow_reset_violation = 1;
        @(negedge clk); resetn = 0;
        #1; awvalid = 1;
        #1; check_negative(12, "D-extra AWVALID during reset between clock edges");
        awvalid = 0; allow_reset_violation = 0;
        defaults; reset_model;
        dut.check_outstanding = 0;
        send_ar(32'h1000, 1);
        @(negedge clk); araddr = 32'h1000; arlen = 0; arvalid = 1;
        repeat (2) begin @(posedge clk); #1; check(!arready, "disabled C11 still backpressures second AR"); end
        @(negedge clk);
        fork
            begin
                get_r(32'h1000, 1, 32'h11, 0, 0, 0, 0, 0);
                get_r(32'h1000, 1, 32'h11, 0, 0, 0, 0, 0);
            end
            begin
                @(posedge clk); while (!arready) @(posedge clk);
                @(negedge clk); arvalid = 0;
            end
        join
        dut.check_outstanding = 1;
        dut.check_quiescent;
        check(negative_tests == 13 && dut.violation_count == 13 && dut.expected_violation_count == 13,
              "all required and additional negative tests detected once");
        $display("PASS: D-extra C11 switch permits queued address without parallel service");
        $display("PASS: T-02a ALL A/B/C/D CHECKS PASSED; mandatory negatives=6/6 total negatives=%0d injections=%0d",
                 negative_tests, dut.injection_count);
        $finish;
    end
endmodule
