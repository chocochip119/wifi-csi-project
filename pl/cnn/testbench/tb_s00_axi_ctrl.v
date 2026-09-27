`timescale 1 ns / 1 ps

// S00-05: write policy verification for the completed CSR implementation.
// TB-only core models cover BUSY_CYCLES=1, 2 and 8. No production Top is added.
// Compile with xvlog -sv. The model does not implement D02 error arbitration.
module tb_s00_axi_ctrl;
    wire done_short, done_boundary, done_long;
    s00_ctrl_case #(.BUSY_CYCLES(1)) short_core    (.finished(done_short));
    s00_ctrl_case #(.BUSY_CYCLES(2)) boundary_core (.finished(done_boundary));
    s00_ctrl_case #(.BUSY_CYCLES(8)) long_core     (.finished(done_long));

    initial begin
        #30000;
        $display("FAIL: S00-05 watchdog timeout");
        $fatal(1, "S00-05 timeout");
    end

    initial begin
        wait (done_short && done_boundary && done_long);
        $display("PASS: S00-05 ALL CONTROL CHECKS PASSED (15a/15b/15c included)");
        $finish;
    end
endmodule

module s00_ctrl_case #(
    parameter integer BUSY_CYCLES = 1
) (
    output reg finished
);
    reg clk, rst_n;
    reg [4:0] awaddr;
    reg awvalid, wvalid, bready;
    reg [31:0] wdata;
    reg [3:0] wstrb;
    wire awready, wready, bvalid;
    wire [1:0] bresp;
    wire reg_start, reg_clear_status;
    wire [31:0] reg_cmd, reg_input_addr, reg_weight_addr, reg_output_addr;

    // Most policy cases control busy directly. Timing cases select the core.
    reg manual_mode, manual_busy;
    reg core_busy, status_done;
    wire status_busy = manual_mode ? manual_busy : core_busy;
    reg [3:0] status_error;
    integer remaining_cycles;
    reg [127:0] core_config;
    reg seed_display;
    reg change_busy_before_commit, commit_busy_value;
    reg [31:0] expected_regs [0:3];
    reg [4:0] rw_addr [0:3];
    reg [4:0] ro_addr [0:2];
    integer aw_count, w_count, commit_count, b_count, start_count, clear_count;
    integer index;
    reg previous_commit, previous_start, previous_clear;
    reg previous_b_stall;
    reg [1:0] held_bresp;
    reg clear_must_keep_busy;
    reg busy_start_commit, last_commit_busy;
    integer last_commit_remaining;
    reg [127:0] busy_start_config;

    pose_cnn_v1_0_S00_AXI dut (
        .reg_start(reg_start), .reg_clear_status(reg_clear_status),
        .reg_cmd(reg_cmd), .reg_input_addr(reg_input_addr),
        .reg_weight_addr(reg_weight_addr), .reg_output_addr(reg_output_addr),
        .status_busy(status_busy), .status_done(status_done),
        .status_error(status_error), .cfg_ok(1'b1), .output_scale_bits(32'h3f800000),
        .S_AXI_ACLK(clk), .S_AXI_ARESETN(rst_n),
        .S_AXI_AWADDR(awaddr), .S_AXI_AWPROT(3'b000),
        .S_AXI_AWVALID(awvalid), .S_AXI_AWREADY(awready),
        .S_AXI_WDATA(wdata), .S_AXI_WSTRB(wstrb),
        .S_AXI_WVALID(wvalid), .S_AXI_WREADY(wready),
        .S_AXI_BRESP(bresp), .S_AXI_BVALID(bvalid), .S_AXI_BREADY(bready),
        .S_AXI_ARADDR(5'b0), .S_AXI_ARPROT(3'b000), .S_AXI_ARVALID(1'b0),
        .S_AXI_ARREADY(), .S_AXI_RDATA(), .S_AXI_RRESP(),
        .S_AXI_RVALID(), .S_AXI_RREADY(1'b1)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task check_condition;
        input condition;
        input [8*120-1:0] message;
        begin
            if (condition !== 1'b1) begin
                $display("FAIL: N=%0d %0s at %0t", BUSY_CYCLES, message, $time);
                $fatal(1, "S00-05 policy mismatch");
            end
        end
    endtask

    task tick;
        begin @(posedge clk); #1; end
    endtask

    task check_regs;
        input [127:0] expected;
        begin
            if ({reg_cmd, reg_input_addr, reg_weight_addr, reg_output_addr} !== expected) begin
                $display("FAIL: N=%0d CSR got=%032h expected=%032h at %0t", BUSY_CYCLES,
                         {reg_cmd, reg_input_addr, reg_weight_addr, reg_output_addr}, expected, $time);
                $fatal(1, "S00-05 register mismatch");
            end
        end
    endtask

    // TB-only core: sample registered START on the next rising edge, snapshot
    // configuration, and stay busy for exactly BUSY_CYCLES complete periods.
    // CLEAR affects display only; it never assigns busy or the countdown.
    always @(posedge clk) begin
        if (!rst_n) begin
            core_busy <= 1'b0;
            remaining_cycles <= 0;
            core_config <= 128'b0;
            status_done <= 1'b0;
            status_error <= 4'b0;
        end else begin
            if (reg_start) begin
                if (!manual_mode) check_condition(!core_busy, "core must not accept a START while busy");
                core_busy <= 1'b1;
                remaining_cycles <= BUSY_CYCLES;
                core_config <= {reg_cmd, reg_input_addr, reg_weight_addr, reg_output_addr};
            end else if (core_busy) begin
                if (remaining_cycles == 1) begin
                    core_busy <= 1'b0;
                    remaining_cycles <= 0;
                end else begin
                    remaining_cycles <= remaining_cycles - 1;
                end
            end
            if (seed_display) begin
                status_done <= 1'b1;
                status_error <= 4'h5;
            end else if (reg_clear_status) begin
                status_done <= 1'b0;
                status_error <= 4'h0;
            end
        end
    end

    // Actual handshake/pulse counts are sampled before NBA updates.
    always @(posedge clk) begin
        if (!rst_n) begin
            previous_commit = 1'b0;
            previous_start = 1'b0;
            previous_clear = 1'b0;
            previous_b_stall = 1'b0;
            held_bresp = 2'b00;
            clear_must_keep_busy = 1'b0;
            busy_start_commit = 1'b0;
            last_commit_busy = 1'b0;
            last_commit_remaining = 0;
            busy_start_config = 128'b0;
        end else begin
            if (reg_start || reg_clear_status)
                check_condition(previous_commit, "registered pulses follow a commit edge");
            check_condition(!(previous_start && reg_start), "START cannot last two cycles");
            check_condition(!(previous_clear && reg_clear_status), "CLEAR cannot last two cycles");
            if (previous_b_stall)
                check_condition(bvalid && bresp === held_bresp, "B response is stable through stall");
            if (bvalid) check_condition({awready, wready} === 2'b00, "B pending blocks new AW/W");
            if (awvalid && awready) aw_count = aw_count + 1;
            if (wvalid && wready) w_count = w_count + 1;
            if (dut.commit_valid) begin
                commit_count = commit_count + 1;
                last_commit_busy = status_busy;
                last_commit_remaining = remaining_cycles;
            end
            // Condition 15c applies to every busy START commit, including the
            // last busy edge. Save pre-NBA inputs, then check registered results.
            busy_start_commit = dut.commit_valid && status_busy
                             && (dut.awaddr_reg[4:2] == 3'd0)
                             && dut.wstrb_reg[0] && dut.wdata_reg[0];
            busy_start_config = {reg_cmd, reg_input_addr, reg_weight_addr, reg_output_addr};
            if (bvalid && bready) b_count = b_count + 1;
            if (reg_start) start_count = start_count + 1;
            if (reg_clear_status) clear_count = clear_count + 1;
            previous_commit = dut.commit_valid;
            previous_start = reg_start;
            previous_clear = reg_clear_status;
            previous_b_stall = bvalid && !bready;
            held_bresp = bresp;
            clear_must_keep_busy = !manual_mode && reg_clear_status && !reg_start
                                && core_busy && (remaining_cycles > 1);
            #1;
            if (busy_start_commit) begin
                check_condition({bvalid, bresp, reg_start, reg_clear_status} === 5'b11000,
                                "every START committed while busy must reject without either pulse");
                check_regs(busy_start_config);
            end
            if (clear_must_keep_busy)
                check_condition(core_busy && !status_done && status_error == 0,
                                "core CLEAR changes display without aborting the active countdown");
        end
    end

    // Expected result is supplied by the scenario, not recomputed with DUT rules.
    // selected=-1 preserves all CSRs; pulse order is {START,CLEAR}.
    task write_check;
        input integer selected;
        input [4:0] address_value;
        input [31:0] data_value;
        input [3:0] strobe_value;
        input [1:0] expected_resp, expected_pulses;
        input [31:0] expected_word;
        input integer stall_cycles;
        input toggle_busy;
        reg [127:0] before_regs, after_regs;
        integer old_commit, old_b, old_start, old_clear, cycle_index;
        begin
            before_regs = {expected_regs[0], expected_regs[1], expected_regs[2], expected_regs[3]};
            after_regs = before_regs;
            if (selected >= 0) after_regs[127-32*selected -: 32] = expected_word;
            old_commit = commit_count; old_b = b_count;
            old_start = start_count; old_clear = clear_count;
            @(negedge clk);
            check_regs(before_regs);
            check_condition({awready, wready, bvalid} === 3'b110, "empty write slot before request");
            awaddr = address_value; wdata = data_value; wstrb = strobe_value;
            awvalid = 1'b1; wvalid = 1'b1; bready = 1'b0;
            tick;
            check_regs(before_regs);
            check_condition({bvalid, reg_start, reg_clear_status} === 3'b000,
                            "capture edge does not commit or pulse early");
            @(negedge clk);
            awvalid = 1'b0; wvalid = 1'b0;
            awaddr = 5'h1f; wdata = 32'hffffffff; wstrb = 4'h0;
            if (change_busy_before_commit) manual_busy = commit_busy_value;
            tick;
            check_regs(after_regs);
            check_condition(commit_count == old_commit+1, "one commit per request");
            check_condition({bvalid, bresp} === {1'b1, expected_resp}, "commit stores expected BRESP");
            check_condition({reg_start, reg_clear_status} === expected_pulses,
                            "commit produces the expected registered pulse pair");
            for (cycle_index = 0; cycle_index < stall_cycles; cycle_index = cycle_index + 1) begin
                @(negedge clk);
                if (toggle_busy) manual_busy = !manual_busy;
                tick;
                check_condition({bvalid, bresp} === {1'b1, expected_resp}, "stalled BRESP cannot be re-decided");
                check_condition({reg_start, reg_clear_status} === 2'b00, "no repeated or delayed pulse during B stall");
                check_regs(after_regs);
            end
            @(negedge clk);
            bready = 1'b1;
            tick;
            check_condition(bvalid === 1'b0, "B response completed");
            check_condition({reg_start, reg_clear_status} === 2'b00, "pulse expires even without B stall");
            check_condition(b_count == old_b+1 && commit_count == old_commit+1, "one commit and B response");
            check_condition(start_count == old_start+expected_pulses[1]
                         && clear_count == old_clear+expected_pulses[0], "exactly one cycle per requested pulse");
            check_regs(after_regs);
            if (expected_pulses[1]) check_condition(core_config === after_regs, "core sampled configuration on START edge");
            {expected_regs[0], expected_regs[1], expected_regs[2], expected_regs[3]} = after_regs;
        end
    endtask

    task control_check;
        input [31:0] data_value;
        input [3:0] strobe_value;
        input [1:0] expected_resp, expected_pulses;
        begin write_check(-1, 5'h00, data_value, strobe_value, expected_resp, expected_pulses, 32'b0, 2, 1'b0); end
    endtask

    // Keep the second request valid through the first B response. BREADY=1
    // throughout, so both AW/W and commit occur at the earliest allowed edges.
    task fastest_second_start;
        integer old_aw, old_w, old_commit, old_b, old_start, old_clear;
        reg [127:0] before_regs;
        reg second_busy;
        begin
            check_condition(!manual_mode && !core_busy, "fast pair uses an idle real core model");
            old_aw = aw_count; old_w = w_count;
            old_commit = commit_count; old_b = b_count;
            old_start = start_count; old_clear = clear_count;
            before_regs = {expected_regs[0], expected_regs[1], expected_regs[2], expected_regs[3]};
            @(negedge clk);
            check_condition({awready, wready, bvalid} === 3'b110, "fast pair starts with empty write slot");
            awaddr = 5'h00; wdata = 32'h1; wstrb = 4'hf;
            awvalid = 1'b1; wvalid = 1'b1; bready = 1'b1;
            tick;
            check_condition(aw_count == old_aw+1 && w_count == old_w+1, "first AW/W captured");
            check_condition({bvalid, reg_start, reg_clear_status} === 3'b000, "first capture has no early pulse");
            tick;
            check_condition(commit_count == old_commit+1, "first commit follows capture by one edge");
            check_condition({bvalid, bresp, reg_start, reg_clear_status} === 5'b10010,
                            "first START is accepted and registered");
            check_condition(!core_busy, "core has not sampled registered START yet");
            tick;
            check_condition(b_count == old_b+1 && aw_count == old_aw+1 && w_count == old_w+1,
                            "first B handshake cannot also capture second AW/W");
            check_condition(core_busy && remaining_cycles == BUSY_CYCLES,
                            "core raises busy on the next START sampling edge");
            check_condition(core_config === before_regs, "first START snapshots the current configuration");
            tick;
            check_condition(aw_count == old_aw+2 && w_count == old_w+2 && commit_count == old_commit+1,
                            "second AW/W captured on first edge after B without early commit");
            @(negedge clk);
            awvalid = 1'b0; wvalid = 1'b0;
            awaddr = 5'h1c; wdata = 32'hffffffff; wstrb = 4'h0;
            @(posedge clk);
            check_condition(dut.commit_valid, "second commit occurs at the earliest possible edge");
            second_busy = status_busy; // pre-NBA: essential for N=2's last busy edge
            #1;
            if (BUSY_CYCLES == 1) begin
                check_condition(second_busy === 1'b0, "N=1 first execution finished before second commit");
                check_condition({bvalid, bresp, reg_start, reg_clear_status} === 5'b10010,
                                "N=1 second START is a new execution: OKAY and one pulse");
            end else begin
                check_condition(second_busy === 1'b1, "N>=2 is busy at second commit");
                check_condition({bvalid, bresp, reg_start, reg_clear_status} === 5'b11000,
                                "N>=2 rejects second START with SLVERR and no pulse");
                if (BUSY_CYCLES == 2)
                    check_condition(!core_busy, "N=2 ends on the rejecting edge; decision still uses pre-edge busy");
            end
            tick;
            check_condition(aw_count == old_aw+2 && w_count == old_w+2
                         && commit_count == old_commit+2 && b_count == old_b+2,
                            "fast pair has exactly two captures, commits and B responses");
            check_condition(start_count == old_start+((BUSY_CYCLES == 1) ? 2 : 1)
                         && clear_count == old_clear, "fast pair emits only accepted START pulses");
            check_condition({reg_start, reg_clear_status} === 2'b00, "second pulse lasts one cycle at most");
            check_regs(before_regs);
            if (BUSY_CYCLES == 1)
                check_condition(core_busy && core_config === before_regs, "N=1 core accepted the second execution");
            while (core_busy) tick;
            repeat (2) tick;
            check_condition(start_count == old_start+((BUSY_CYCLES == 1) ? 2 : 1)
                         && clear_count == old_clear && commit_count == old_commit+2 && b_count == old_b+2,
                            "no late pulse or replay after the core returns idle");
            if (BUSY_CYCLES == 1)
                $display("PASS: 15b N=1 fastest second START: commit busy=0 -> OKAY, second 1-cycle pulse");
            else
                $display("PASS: 15a N=%0d fastest second START: commit busy=1 -> SLVERR, no second pulse", BUSY_CYCLES);
        end
    endtask

    // For N=8, consecutive commits hit remaining=7, 4 and 1. The last request
    // is decided on the same edge that the core drops busy through NBA.
    task starts_across_busy_window;
        integer old_start;
        begin
            check_condition(BUSY_CYCLES == 8 && !manual_mode && !core_busy,
                            "busy-window test requires the idle N=8 core");
            old_start = start_count;
            write_check(-1, 5'h00, 32'h1, 4'hf, 2'b00, 2'b10, 32'b0, 0, 0);
            write_check(-1, 5'h00, 32'h1, 4'hf, 2'b10, 2'b00, 32'b0, 0, 0);
            check_condition(last_commit_busy && last_commit_remaining == 7,
                            "early START committed while busy with 7 cycles remaining");
            $display("PASS: 15c N=8 early busy START: remaining=7 -> SLVERR, no pulse");
            write_check(-1, 5'h00, 32'h1, 4'hf, 2'b10, 2'b00, 32'b0, 0, 0);
            check_condition(last_commit_busy && last_commit_remaining == 4,
                            "middle START committed while busy with 4 cycles remaining");
            $display("PASS: 15c N=8 middle busy START: remaining=4 -> SLVERR, no pulse");
            write_check(-1, 5'h00, 32'h1, 4'hf, 2'b10, 2'b00, 32'b0, 0, 0);
            check_condition(last_commit_busy && last_commit_remaining == 1 && !core_busy,
                            "last START committed on the final busy edge and remained rejected after idle");
            repeat (2) tick;
            check_condition(start_count == old_start+1 && {reg_start, reg_clear_status} === 2'b00,
                            "busy-window attempts never start an extra execution or delayed pulse");
            $display("PASS: 15c N=8 final busy START: remaining=1 -> SLVERR, no pulse after busy drops");
        end
    endtask

    initial begin
        finished = 1'b0;
        rst_n = 1'b1;
        awaddr = 5'b0; awvalid = 1'b0; wdata = 32'b0; wstrb = 4'b0;
        wvalid = 1'b0; bready = 1'b0;
        manual_mode = 1'b1; manual_busy = 1'b0; seed_display = 1'b0;
        change_busy_before_commit = 1'b0; commit_busy_value = 1'b0;
        aw_count = 0; w_count = 0; commit_count = 0; b_count = 0; start_count = 0; clear_count = 0;
        expected_regs[0] = 0; expected_regs[1] = 0; expected_regs[2] = 0; expected_regs[3] = 0;
        rw_addr[0] = 5'h08; rw_addr[1] = 5'h0c; rw_addr[2] = 5'h10; rw_addr[3] = 5'h14;
        ro_addr[0] = 5'h04; ro_addr[1] = 5'h18; ro_addr[2] = 5'h1c;
        #2 rst_n = 1'b0;
        #1;
        tick;
        // Synchronous reset takes effect at the rising edge (R-01).
        check_condition({reg_start, reg_clear_status, bresp} === 4'b0000, "reset clears pulses and BRESP");
        @(posedge clk); rst_n <= 1'b1; #1;
        check_condition({reg_start, reg_clear_status, awready, wready, bvalid} === 5'b0,
                        "immediate reset release keeps outputs inactive");
        tick;
        $display("PASS: N=%0d reset clears both control pulses and BRESP", BUSY_CYCLES);

        write_check(0, 5'h08, 32'h89abcdef, 4'hf, 2'b00, 2'b00, 32'h89abcdef, 0, 0);
        write_check(1, 5'h0c, 32'h10203040, 4'hf, 2'b00, 2'b00, 32'h10203040, 0, 0);
        write_check(2, 5'h10, 32'h50607080, 4'hf, 2'b00, 2'b00, 32'h50607080, 0, 0);
        write_check(3, 5'h14, 32'h90a0b0c0, 4'hf, 2'b00, 2'b00, 32'h90a0b0c0, 0, 0);
        control_check(32'h1, 4'hf, 2'b00, 2'b10);
        $display("PASS: N=%0d idle START is one registered cycle after commit; core snapshots configuration", BUSY_CYCLES);
        @(negedge clk); seed_display = 1'b1;
        tick;
        @(negedge clk); seed_display = 1'b0;
        control_check(32'h2, 4'hf, 2'b00, 2'b01);
        check_condition({status_done, status_error} === 5'b0, "TB display cleared by CLEAR pulse");
        $display("PASS: N=%0d idle CLEAR pulses once; TB display clears", BUSY_CYCLES);
        control_check(32'h3, 4'hf, 2'b00, 2'b11);
        $display("PASS: N=%0d idle START+CLEAR emits both pulses in the same cycle", BUSY_CYCLES);

        @(negedge clk); manual_busy = 1'b1;
        control_check(32'h1, 4'hf, 2'b10, 2'b00);
        control_check(32'h3, 4'hf, 2'b10, 2'b00);
        $display("PASS: N=%0d busy START and START+CLEAR reject atomically without pulses", BUSY_CYCLES);
        control_check(32'h2, 4'hf, 2'b00, 2'b01);
        check_condition(status_busy === 1'b1, "CLEAR does not drive CSR busy low");
        $display("PASS: N=%0d busy CLEAR-only is OKAY and emits CLEAR", BUSY_CYCLES);
        control_check(32'hffffffff, 4'he, 2'b00, 2'b00);
        control_check(32'h3, 4'h0, 2'b00, 2'b00);
        control_check(32'hfffffffc, 4'hf, 2'b00, 2'b00);
        @(negedge clk); manual_busy = 1'b0;
        control_check(32'hffffffff, 4'he, 2'b00, 2'b00);
        control_check(32'h3, 4'h0, 2'b00, 2'b00);
        control_check(32'hfffffffc, 4'hf, 2'b00, 2'b00);
        $display("PASS: N=%0d CONTROL lane-0 masking and reserved bits work in idle and busy", BUSY_CYCLES);

        @(negedge clk); manual_busy = 1'b1;
        for (index = 0; index < 4; index = index + 1) begin
            write_check(index, rw_addr[index], 32'hffffffff, 4'hf, 2'b10, 2'b00, expected_regs[index], 0, 0);
            write_check(index, rw_addr[index], 32'hffffffff, 4'h0, 2'b10, 2'b00, expected_regs[index], 0, 0);
        end
        $display("PASS: N=%0d all 4 busy RW registers reject full and zero strobes; every value preserved", BUSY_CYCLES);
        for (index = 0; index < 3; index = index + 1) begin
            write_check(-1, ro_addr[index], 32'hffffffff, 4'hf, 2'b00, 2'b00, 32'b0, 0, 0);
            write_check(-1, ro_addr[index], 32'hffffffff, 4'h0, 2'b00, 2'b00, 32'b0, 0, 0);
        end
        $display("PASS: N=%0d busy RO/reserved writes ignore data/strobes and return OKAY", BUSY_CYCLES);

        @(negedge clk); manual_busy = 1'b0;
        for (index = 1; index < 4; index = index + 1) begin
            write_check(index, rw_addr[index], 32'hdeadbeff, 4'hf, 2'b10, 2'b00, expected_regs[index], 0, 0);
            write_check(index, rw_addr[index], 32'h00000001, 4'h1, 2'b10, 2'b00, expected_regs[index], 0, 0);
        end
        // OUTPUT needs 32-byte alignment: 0x08 is 8-byte aligned but still invalid.
        write_check(3, 5'h14, 32'h12345608, 4'hf, 2'b10, 2'b00, expected_regs[3], 0, 0);
        write_check(0, 5'h08, 32'hdeadbeff, 4'hf, 2'b00, 2'b00, 32'hdeadbeff, 0, 0);
        $display("PASS: N=%0d DDR full/partial misalignment rejects the entire candidate; COMMAND is exempt", BUSY_CYCLES);
        write_check(1, 5'h0c, 32'hdeadbe07, 4'he, 2'b00, 2'b00, 32'hdeadbe40, 0, 0);
        write_check(2, 5'h10, 32'hcafeba07, 4'he, 2'b00, 2'b00, 32'hcafeba80, 0, 0);
        write_check(3, 5'h14, 32'h1234561f, 4'he, 2'b00, 2'b00, 32'h123456c0, 0, 0);
        for (index = 0; index < 4; index = index + 1)
            write_check(index, rw_addr[index], 32'hffffffff, 4'h0, 2'b00, 2'b00, expected_regs[index], 0, 0);
        $display("PASS: N=%0d alignment uses merged bytes; unselected bad low bits and idle zero strobes are harmless", BUSY_CYCLES);

        // Accepted pulse: later busy changes cannot extend or repeat it.
        write_check(-1, 5'h00, 32'h3, 4'hf, 2'b00, 2'b11, 32'b0, 4, 1);
        @(negedge clk); manual_busy = 1'b1;
        write_check(-1, 5'h00, 32'h3, 4'hf, 2'b10, 2'b00, 32'b0, 4, 1);
        $display("PASS: N=%0d stalled OKAY/SLVERR stay fixed across busy 0<->1; no extended or late pulses", BUSY_CYCLES);

        // Change busy after AW/W capture but before commit, in both directions.
        @(negedge clk);
        manual_busy = 1'b0; change_busy_before_commit = 1'b1; commit_busy_value = 1'b1;
        write_check(0, 5'h08, 32'h01020304, 4'hf, 2'b10, 2'b00, expected_regs[0], 0, 0);
        @(negedge clk); manual_busy = 1'b1; commit_busy_value = 1'b0;
        write_check(0, 5'h08, 32'h01020304, 4'hf, 2'b00, 2'b00, 32'h01020304, 0, 0);
        change_busy_before_commit = 1'b0;
        $display("PASS: N=%0d rejection samples busy at commit, not at AW/W capture", BUSY_CYCLES);

        // Check the model contract with actual core busy (no manual override).
        while (core_busy) tick;
        @(negedge clk); manual_mode = 1'b0;
        write_check(-1, 5'h00, 32'h1, 4'hf, 2'b00, 2'b10, 32'b0, 0, 0);
        for (index = 0; index < BUSY_CYCLES; index = index + 1) begin
            check_condition(core_busy, "core busy holds for the requested number of cycles");
            tick;
        end
        check_condition(!core_busy, "core busy releases after exactly N cycles");
        $display("PASS: N=%0d core raises busy on START sampling edge and holds exactly N cycles", BUSY_CYCLES);
        if (BUSY_CYCLES == 8) begin
            @(negedge clk); seed_display = 1'b1;
            tick;
            @(negedge clk); seed_display = 1'b0;
            write_check(-1, 5'h00, 32'h1, 4'hf, 2'b00, 2'b10, 32'b0, 0, 0);
            write_check(-1, 5'h00, 32'h2, 4'hf, 2'b00, 2'b01, 32'b0, 0, 0);
            check_condition(core_busy && !status_done && status_error == 0,
                            "CLEAR completed while real core countdown remains active");
            while (core_busy) tick;
            $display("PASS: N=8 CLEAR updates display while the core keeps running");
        end

        // D03 R2-1 / corrected conditions 15a, 15b and 15c (2026-09-24).
        fastest_second_start;
        if (BUSY_CYCLES == 8) starts_across_busy_window;
        check_condition(aw_count == commit_count && w_count == commit_count && commit_count == b_count,
                        "all accepted policy transactions completed exactly once");
        $display("PASS: N=%0d totals commit=%0d B=%0d START=%0d CLEAR=%0d", BUSY_CYCLES,
                 commit_count, b_count, start_count, clear_count);
        finished = 1'b1;
    end
endmodule
