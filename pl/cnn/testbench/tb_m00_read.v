`timescale 1ns / 1ps

// T-02b read-only verification fixture, shared by the two separately selected
// simulation tops. Production M00 and the T-02a slave are instantiated as-is.
module m00_read_fixture;
    reg clk = 0, resetn = 0;
    always #5 clk = ~clk;
    reg mem_rd_start = 0, mem_rd_ready = 1;
    reg [31:0] mem_rd_addr = 0;
    reg [19:0] mem_rd_bytes = 0;
    wire mem_rd_busy, mem_rd_valid, mem_rd_err;
    wire [63:0] mem_rd_data;
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
        .mem_wr_start(1'b0), .mem_wr_addr(32'b0), .mem_wr_bytes(20'b0), .mem_wr_data(64'b0),
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

    integer cycle_count = 0;
    bit active = 0, finished = 0, started = 0;
    string case_name;
    reg [31:0] request_addr, pattern_seed;
    integer request_bytes, expected_words;
    reg [63:0] collected_words[];
    reg [31:0] issued_addr[];
    integer issued_beats[];
    integer word_count, ar_count, ar_words, current_burst_left;
    integer accepted_starts, ignored_starts, start_cycle, finish_cycle;
    integer first_word_cycle, last_word_cycle, prior_burst_end;
    integer inter_burst_idle, busy_samples, held_valid_cycles, ar_stall_cycles;
    integer literal_ready_mismatches, active_ready_checks, ar_payload_checks;
    integer short_nonfinal, covered_bytes;
    integer total_cycles, startup_idle;
    integer consumer_mode = 0, hold_left = 0, hold_low_cycles = 0;
    bit hold_used = 0, previously_stalled = 0, previous_start = 0;
    reg [63:0] held_data;
    bit sampled_busy, sampled_transfer, accepted_this_edge;
    integer samples_before_hold;
    integer trace_file = 0;
    string trace_path;

    task automatic check(input bit condition, input string message);
        if (!condition) begin
            $display("FAIL: %s: %s at cycle=%0d time=%0t", case_name, message, cycle_count, $time);
            $fatal(1, "T-02b read check failed");
        end
    endtask

    function automatic [63:0] expected_word(input reg [31:0] addr, seed);
        expected_word = {seed ^ 32'hA5C3_9E71, addr ^ seed};
    endfunction

    initial begin
        if ($value$plusargs("AR_TRACE=%s", trace_path)) begin
            trace_file = $fopen(trace_path, "w");
            if (trace_file == 0) $fatal(1, "cannot open AR trace");
            $fdisplay(trace_file, "case,burst_index,address_hex,beats,end_exclusive_hex");
        end
    end

    task automatic reset_fixture;
        begin
            @(negedge clk); active = 0; mem_rd_start = 0; mem_rd_ready = 1; resetn = 0;
            repeat (3) begin @(posedge clk); #2; end
            @(negedge clk); resetn = 1;
            repeat (2) begin @(posedge clk); #2; end
            check(!mem_rd_busy && !mem_rd_valid && !mem_rd_err, "reset read interface idle");
            @(negedge clk);
            check(memory.check_outstanding == 1, "C11 remains enabled");
        end
    endtask

    // All stimuli change on falling edges; all evidence samples use the
    // pre-NBA handshake values at rising edges. Busy is also checked post-NBA.
    always @(negedge clk) begin
        if (resetn && active) begin
            case (consumer_mode)
                0: mem_rd_ready = 1;
                1: begin
                    if (!hold_used && word_count >= 3) begin
                        hold_used = 1; hold_left = 8; samples_before_hold = word_count;
                    end
                    if (hold_left > 0) begin
                        mem_rd_ready = 0; hold_left = hold_left - 1;
                        hold_low_cycles = hold_low_cycles + 1;
                        check(word_count == samples_before_hold, "no data accepted during 8-clock ready hold");
                    end else mem_rd_ready = 1;
                end
                2: mem_rd_ready = cycle_count % 2 == 0;
                default: $fatal(1, "unknown consumer mode");
            endcase
        end
    end

    always @(posedge clk) begin
        cycle_count = cycle_count + 1;
        if (!resetn) begin previously_stalled = 0; previous_start = 0; end
        else begin
            check(!mem_wr_busy && !mem_wr_ready && !mem_wr_err && !M_AXI_AWVALID && !M_AXI_WVALID,
                  "write interface stays inactive");
            check(memory.check_outstanding == 1, "C11 may not be disabled");
            if (!active) check(!mem_rd_valid && !M_AXI_ARVALID, "no unsolicited/late read after completion");
            else begin
                sampled_busy = mem_rd_busy;
                sampled_transfer = mem_rd_valid && mem_rd_ready;
                accepted_this_edge = mem_rd_start && !sampled_busy;
                check(!(mem_rd_start && previous_start), "START is exactly one sampled cycle");
                previous_start = mem_rd_start;
                if (accepted_this_edge) begin
                    accepted_starts = accepted_starts + 1; started = 1; start_cycle = cycle_count;
                    check(accepted_starts == 1, "exactly one accepted START");
                end else if (mem_rd_start) ignored_starts = ignored_starts + 1;
                if (sampled_busy) busy_samples = busy_samples + 1;
                check(!mem_rd_err, "no read error on normal traffic");
                check(mem_rd_data === M_AXI_RDATA, "mem_rd_data equals RDATA");
                check(sampled_transfer === (M_AXI_RVALID && M_AXI_RREADY), "core and AXI accept exactly the same beats");
                if (mem_rd_ready !== M_AXI_RREADY) literal_ready_mismatches = literal_ready_mismatches + 1;
                if (M_AXI_RVALID) begin
                    check(mem_rd_valid && M_AXI_RREADY === mem_rd_ready, "R6 direct ready/valid during offered R data");
                    active_ready_checks = active_ready_checks + 1;
                end
                if (previously_stalled)
                    check(mem_rd_valid && mem_rd_data === held_data, "VALID and DATA stable across consumer stall");
                previously_stalled = mem_rd_valid && !mem_rd_ready;
                held_data = mem_rd_data;
                if (previously_stalled) held_valid_cycles = held_valid_cycles + 1;

                if (M_AXI_ARVALID) begin
                    check({M_AXI_ARID,M_AXI_ARSIZE,M_AXI_ARBURST,M_AXI_ARLOCK,M_AXI_ARCACHE,M_AXI_ARPROT,M_AXI_ARQOS}
                          === {1'b0,3'b011,2'b01,1'b0,4'b0011,3'b000,4'b0000}, "all AR constants including LOCK/CACHE/PROT/QOS");
                    ar_payload_checks = ar_payload_checks + 1;
                    if (!M_AXI_ARREADY) ar_stall_cycles = ar_stall_cycles + 1;
                end
                if (M_AXI_ARVALID && M_AXI_ARREADY) begin
                    check(started && sampled_busy, "AR must belong to busy command");
                    check(ar_count < expected_words, "AR collection capacity");
                    check(current_burst_left == 0, "one read burst outstanding in TB scoreboard");
                    issued_addr[ar_count] = M_AXI_ARADDR;
                    issued_beats[ar_count] = int'(M_AXI_ARLEN) + 1;
                    check(M_AXI_ARADDR == request_addr+ar_words*8, "AR range is contiguous/in order without gaps or overlaps");
                    check(ar_words+issued_beats[ar_count] <= expected_words, "AR cannot overrun requested range");
                    current_burst_left = issued_beats[ar_count];
                    ar_words = ar_words + current_burst_left;
                    ar_count = ar_count + 1;
                end
                if (sampled_transfer) begin
                    check(sampled_busy && word_count < expected_words, "busy remains high through final transfer; no extra word");
                    check(current_burst_left > 0, "R data has an accepted AR");
                    if (current_burst_left == issued_beats[ar_count-1]) begin
                        if (prior_burst_end >= 0)
                            inter_burst_idle = inter_burst_idle + cycle_count-prior_burst_end-1;
                    end
                    check(M_AXI_RLAST === (current_burst_left == 1), "one RLAST exactly at each issued AR end");
                    if (word_count == 0) first_word_cycle = cycle_count;
                    collected_words[word_count] = mem_rd_data;
                    word_count = word_count + 1; current_burst_left = current_burst_left - 1;
                    last_word_cycle = cycle_count;
                    if (current_burst_left == 0) prior_burst_end = cycle_count;
                end
                #1;
                if (accepted_this_edge) check(mem_rd_busy, "busy asserts after START sampling edge");
                if (started && sampled_busy && !mem_rd_busy) begin
                    check(sampled_transfer && word_count == expected_words && current_burst_left == 0,
                          "busy falls only immediately after final accepted word");
                    finish_cycle = cycle_count; finished = 1;
                end else if (started && !finished) check(mem_rd_busy, "busy cannot drop before final word");
            end
        end
    end

    // Recompute the range from the complete collected AR list, independently
    // of DUT burst_beats(). Non-final short bursts must end at a 4-KiB boundary.
    task automatic audit_full_results(input integer expected_bursts);
        integer j, remain_words, boundary_words, planned_words;
        reg [32:0] cursor, limit_addr;
        begin
            check(word_count == expected_words, "all requested words were collected");
            for (j = 0; j < expected_words; j = j + 1) begin
                check(collected_words[j] === expected_word(request_addr+j*8, pattern_seed),
                      $sformatf("full-sequence comparison word=%0d addr=%08h", j, request_addr+j*8));
                check(collected_words[j] === memory.mem_word(request_addr+j*8), "collected sequence matches memory contents");
            end
            cursor = {1'b0,request_addr}; limit_addr = cursor+request_bytes;
            covered_bytes = 0; short_nonfinal = 0;
            for (j = 0; j < ar_count; j = j + 1) begin
                check({1'b0,issued_addr[j]} == cursor, "offline AR cover has no gap/overlap/reordering");
                remain_words = (limit_addr-cursor)/8;
                boundary_words = (4096-int'(cursor[11:0]))/8;
                planned_words = remain_words;
                if (planned_words > 16) planned_words = 16;
                if (planned_words > boundary_words) planned_words = boundary_words;
                check(issued_beats[j] == planned_words, "ARLEN matches remaining bytes, 16-beat cap and 4-KiB boundary");
                if (j < ar_count-1 && issued_beats[j] < 16) begin
                    check((cursor+issued_beats[j]*8)%4096 == 0, "non-final short burst is necessary boundary split");
                    short_nonfinal = short_nonfinal + 1;
                end
                cursor = cursor + issued_beats[j]*8;
                covered_bytes = covered_bytes + issued_beats[j]*8;
                if (trace_file != 0)
                    $fdisplay(trace_file, "%s,%0d,%08h,%0d,%09h", case_name,j,issued_addr[j],issued_beats[j],cursor);
            end
            check(cursor == limit_addr && covered_bytes == request_bytes && ar_words == expected_words,
                  "complete issued AR list covers exact requested interval");
            check(ar_count == expected_bursts, "observed burst count equals independent expected count");
            check(accepted_starts == 1 && busy_samples == finish_cycle-start_cycle, "busy high has no holes");
            check(memory.violation_count == 0, "model protocol violations must be zero");
            check(!mem_rd_busy && !mem_rd_err, "command ended cleanly");
            memory.check_quiescent;
        end
    endtask

    task automatic run_read(input string label_text, input reg [31:0] addr,
        input integer bytes, input reg [31:0] seed, input integer expected_bursts,
        input integer ready_mode, input bit exercise_start);
        begin
            @(negedge clk);
            check(!active && !mem_rd_busy, "new test begins idle");
            case_name = label_text; request_addr = addr; request_bytes = bytes; pattern_seed = seed;
            expected_words = bytes/8;
            collected_words = new[expected_words]; issued_addr = new[expected_words]; issued_beats = new[expected_words];
            memory.mem_fill(addr, bytes, seed);
            word_count = 0; ar_count = 0; ar_words = 0; current_burst_left = 0;
            accepted_starts = 0; ignored_starts = 0; busy_samples = 0;
            held_valid_cycles = 0; ar_stall_cycles = 0; literal_ready_mismatches = 0;
            active_ready_checks = 0; ar_payload_checks = 0; inter_burst_idle = 0; prior_burst_end = -1;
            hold_used = 0; hold_left = 0; hold_low_cycles = 0; consumer_mode = ready_mode;
            previously_stalled = 0; previous_start = 0; finished = 0; started = 0; active = 1;
            mem_rd_ready = 1; mem_rd_addr = addr; mem_rd_bytes = bytes; mem_rd_start = 1;
            #1; check(!mem_rd_busy, "START does not assert busy before its sampling edge");
            @(posedge clk); #2;
            check(mem_rd_busy && accepted_starts == 1, "START snapshot accepted and busy high next cycle");
            @(negedge clk); mem_rd_start = 0;
            // Deliberately change both inputs after every command snapshot.
            mem_rd_addr = 32'hee001000; mem_rd_bytes = 20'd8;
            if (exercise_start) begin
                repeat (2) @(negedge clk);
                check(mem_rd_busy, "ignored START test occurs while busy");
                mem_rd_start = 1;
                @(negedge clk); mem_rd_start = 0;
            end
            while (!finished) begin
                @(posedge clk); #2;
                check(cycle_count-start_cycle < 2000000, "TB completion timeout (RTL watchdog remains disabled)");
            end
            @(negedge clk); active = 0; mem_rd_ready = 1;
            total_cycles = finish_cycle-start_cycle;
            startup_idle = first_word_cycle-start_cycle-1;
            audit_full_results(expected_bursts);
            check(ignored_starts == (exercise_start ? 1 : 0), "busy START sampled once and ignored");
            if (ready_mode == 1)
                check(hold_low_cycles == 8 && held_valid_cycles >= 8, "8-clock hold actually stalls valid data");
            if (ready_mode == 2) check(held_valid_cycles > 0, "alternating READY actually stalls valid data");
            $display("PASS: %s R1/R2 snapshot+busy words=%0d bursts=%0d expected=%0d cycles=%0d busy_samples=%0d accepted_start=%0d ignored_start=%0d",
                     case_name, word_count, ar_count, expected_bursts, total_cycles, busy_samples, accepted_starts, ignored_starts);
            $display("PASS: %s R3/R4/R5 cover_bytes=%0d compared_words=%0d AR_constant_checks=%0d nonfinal_boundary_short=%0d",
                     case_name, covered_bytes, word_count, ar_payload_checks, short_nonfinal);
            $display("PASS: %s R6 transfer/stall ready_checks=%0d held_valid_cycles=%0d ar_wait=%0d protocol_violations=%0d",
                     case_name, active_ready_checks, held_valid_cycles, ar_stall_cycles, memory.violation_count);
            $display("OBSERVATION: %s literal_RREADY_direct_mismatch_cycles=%0d (state-qualified RTL; data-phase equality passed)",
                     case_name, literal_ready_mismatches);
            if (short_nonfinal != 0)
                $display("SPEC_NOTE: %s has %0d legal non-final short burst(s) ending at 4-KiB boundaries", case_name, short_nonfinal);
            // Detect ignored START being queued for an unsolicited later read.
            repeat (4) begin @(posedge clk); #2; check(!mem_rd_busy && !mem_rd_valid, "idle after completion; no queued busy START"); end
        end
    endtask

    task automatic close_fixture;
        begin
            memory.check_quiescent;
            check(memory.violation_count == 0 && memory.injection_count == 0, "no protocol violation or error injection");
            if (trace_file != 0) $fclose(trace_file);
        end
    endtask
endmodule

module tb_m00_read;
    m00_read_fixture env();
    initial begin #10000000; $fatal(1, "FAIL: functional TB global timeout"); end
    initial begin
        env.reset_fixture;
        env.run_read("size_8", 32'h1e000000, 8, 32'h101, 1, 0, 0);
        env.run_read("size_128", 32'h1e000100, 128, 32'h102, 1, 0, 0);
        env.run_read("size_136_snapshot_busy_start", 32'h1e000200, 136, 32'h103, 2, 0, 1);
        env.run_read("boundary_before", 32'h1e001ff8, 136, 32'h104, 2, 0, 0);
        env.run_read("boundary_exact", 32'h1e002000, 136, 32'h105, 2, 0, 0);
        env.run_read("boundary_after", 32'h1e002008, 4096, 32'h106, 33, 0, 0);
        env.run_read("load_part1", 32'h1e020000, 5936, 32'h107, 47, 0, 0);
        env.run_read("load_part2", 32'h1e020000+399152, 23840, 32'h108, 187, 0, 0);
        env.run_read("ready_hold_8", 32'h1e030000, 136, 32'h109, 2, 1, 0);
        env.run_read("ready_alternate", 32'h1e030100, 512, 32'h10a, 4, 2, 0);
        env.memory.ar_ready_mode = 1; env.memory.ar_gap_cycles = 7; env.memory.r_gap_cycles = 2;
        env.run_read("combined_periodic_stalls", 32'h1e030300, 512, 32'h10b, 4, 2, 0);
        env.check(env.ar_stall_cycles > 0, "periodic slave ARREADY actually delays requests");
        env.memory.ar_ready_mode = 2; env.memory.ar_seed = 32'h13572468; env.memory.r_gap_cycles = 2;
        env.run_read("combined_random_stalls", 32'h1e030600, 512, 32'h10c, 4, 2, 0);
        env.check(env.ar_stall_cycles > 0, "random slave ARREADY actually delays requests");
        env.close_fixture;
        $display("PASS: T-02b FUNCTIONAL 12/12 CASES, ALL COLLECTED WORDS AND AR RANGES CHECKED; protocol violations=0");
        $display("REVIEW: literal R3 last-short-only excludes necessary 4-KiB splits; literal R6 direct RREADY differs outside RD_DATA; no RTL/model edits");
        $finish;
    end
endmodule
