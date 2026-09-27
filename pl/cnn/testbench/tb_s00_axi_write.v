`timescale 1 ns / 1 ps

// S00-02 handshake regression, adapted to the completed S00-05 CSR policy.
// Checks AW/W capture, commit payload, B response, reset, and concurrent reads.
// Compile this testbench with SystemVerilog support for $fatal.
module tb_s00_axi_write;
    reg clk;
    reg rst_n;
    reg [4:0] awaddr;
    reg awvalid;
    wire awready;
    reg [31:0] wdata;
    reg [3:0] wstrb;
    reg wvalid;
    wire wready;
    wire [1:0] bresp;
    wire bvalid;
    reg bready;
    wire arready, rvalid;
    wire [31:0] rdata;
    wire [1:0] rresp;
    wire reg_start, reg_clear_status;
    wire [31:0] reg_cmd, reg_input_addr, reg_weight_addr, reg_output_addr;

    integer aw_count, w_count, commit_count, b_count;
    reg [4:0] expected_addr [0:4];
    reg [31:0] expected_data [0:4];
    reg [3:0] expected_strb [0:4];
    reg [212:0] reset_registers_before;
    reg [4:0] reset_outputs_before;

    pose_cnn_v1_0_S00_AXI #(
        .C_S_AXI_DATA_WIDTH(32),
        .C_S_AXI_ADDR_WIDTH(5)
    ) dut (
        .reg_start(reg_start),
        .reg_clear_status(reg_clear_status),
        .reg_cmd(reg_cmd),
        .reg_input_addr(reg_input_addr),
        .reg_weight_addr(reg_weight_addr),
        .reg_output_addr(reg_output_addr),
        // Idle and aligned writes preserve the original handshake scenarios.
        .status_busy(1'b0),
        .status_done(1'b1),
        .status_error(4'hf),
        .cfg_ok(1'b1),
        .output_scale_bits(32'h3f800000),
        .S_AXI_ACLK(clk),
        .S_AXI_ARESETN(rst_n),
        .S_AXI_AWADDR(awaddr),
        .S_AXI_AWPROT(3'b101),
        .S_AXI_AWVALID(awvalid),
        .S_AXI_AWREADY(awready),
        .S_AXI_WDATA(wdata),
        .S_AXI_WSTRB(wstrb),
        .S_AXI_WVALID(wvalid),
        .S_AXI_WREADY(wready),
        .S_AXI_BRESP(bresp),
        .S_AXI_BVALID(bvalid),
        .S_AXI_BREADY(bready),
        .S_AXI_ARADDR(5'h18),
        .S_AXI_ARPROT(3'b111),
        .S_AXI_ARVALID(1'b1),
        .S_AXI_ARREADY(arready),
        .S_AXI_RDATA(rdata),
        .S_AXI_RRESP(rresp),
        .S_AXI_RVALID(rvalid),
        .S_AXI_RREADY(1'b1)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task check_condition;
        input condition;
        input [8*120-1:0] message;
        begin
            if (condition !== 1'b1) begin
                $display("FAIL: %0s at %0t", message, $time);
                $fatal(1, "S00-02 test failed");
            end
        end
    endtask

    // Checks after a tick see NBA updates. The scoreboard below samples the
    // pre-NBA edge values, which are the values actually handshaken/committed.
    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task send_pair;
        input [4:0] address_value;
        input [31:0] data_value;
        input [3:0] strobe_value;
        begin
            @(negedge clk);
            check_condition(awready && wready, "send_pair requires empty AW/W entries");
            awaddr = address_value;
            wdata = data_value;
            wstrb = strobe_value;
            awvalid = 1'b1;
            wvalid = 1'b1;
            tick;
            @(negedge clk);
            awvalid = 1'b0;
            wvalid = 1'b0;
            // Change bus inputs after acceptance: commit must use held payload.
            awaddr = 5'h1f;
            wdata = 32'hdeadbeef;
            wstrb = 4'h0;
        end
    endtask

    task complete_response;
        input integer expected_total;
        begin
            while (bvalid !== 1'b1) tick;
            @(negedge clk);
            bready = 1'b1;
            tick;
            check_condition(b_count == expected_total, "one B handshake per transaction");
            check_condition(commit_count == expected_total, "one commit per transaction");
            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    // R-01 b-2: enter just after tick (#1 after posedge). The entire low pulse
    // is between rising edges: outputs are gated, but no register is reset.
    // This documents why the supplied reset must cover at least one clock
    // period; a pulse that misses every rising edge is NOT a valid reset.
    task check_short_reset_pulse;
        begin
            reset_registers_before = {dut.wr_state_reg, dut.channel_enable_reg,
                dut.aw_hold_reg, dut.w_hold_reg, dut.awaddr_reg, dut.wdata_reg,
                dut.wstrb_reg, dut.cmd_reg, dut.input_addr_reg, dut.weight_addr_reg,
                dut.output_addr_reg, dut.bresp_reg, dut.start_reg, dut.clear_status_reg,
                dut.rvalid_reg, dut.rdata_reg, dut.rresp_reg};
            reset_outputs_before = {awready, wready, bvalid, arready, rvalid};
            check_condition(reg_cmd !== 32'b0, "short-pulse test starts with nonzero stored CSR");
            #1 rst_n = 1'b0;
            #1;
            check_condition({awready, wready, bvalid, arready, rvalid} === 5'b00000,
                            "short pulse gates all five AXI READY/VALID outputs low");
            check_condition({dut.wr_state_reg, dut.channel_enable_reg,
                dut.aw_hold_reg, dut.w_hold_reg, dut.awaddr_reg, dut.wdata_reg,
                dut.wstrb_reg, dut.cmd_reg, dut.input_addr_reg, dut.weight_addr_reg,
                dut.output_addr_reg, dut.bresp_reg, dut.start_reg, dut.clear_status_reg,
                dut.rvalid_reg, dut.rdata_reg, dut.rresp_reg} === reset_registers_before,
                            "pulse without a rising edge preserves every sequential register");
            #1 rst_n = 1'b1;
            #1;
            check_condition({awready, wready, bvalid, arready, rvalid} === reset_outputs_before,
                            "short pulse removal restores outputs from retained state");
        end
    endtask

    always @(posedge clk) begin
        if (rst_n) begin
            check_condition(!rvalid || (rdata === 32'h3f800000 && rresp === 2'b00),
                            "concurrent 0x18 reads return scale/OKAY and do not disturb writes");
            check_condition({reg_start, reg_clear_status} === 2'b00,
                            "these non-CONTROL writes produce no pulses");
            check_condition(bresp === 2'b00, "these idle aligned writes return OKAY");

            // These checks also cover the B handshake edge, before state changes.
            if (bvalid) begin
                check_condition({awready, wready} === 2'b00, "no AW/W acceptance in WR_RESP");
            end
            if (awvalid && awready) aw_count = aw_count + 1;
            if (wvalid && wready) w_count = w_count + 1;
            if (dut.commit_valid) begin
                check_condition(commit_count < 5, "no unexpected/duplicate commit");
                check_condition(aw_count == commit_count + 1 && w_count == commit_count + 1,
                                "commit follows exactly one AW and one W acceptance");
                check_condition(dut.awaddr_reg === expected_addr[commit_count], "commit address matches");
                check_condition(dut.wdata_reg === expected_data[commit_count], "commit data matches");
                check_condition(dut.wstrb_reg === expected_strb[commit_count], "commit strobe matches");
                commit_count = commit_count + 1;
            end
            if (bvalid && bready) begin
                check_condition(b_count < commit_count, "B response requires an unresponded commit");
                b_count = b_count + 1;
            end
        end
    end

    initial begin
        // Bounded failure if a missing READY/response would otherwise hang a task.
        #10000;
        $display("FAIL: watchdog timeout");
        $fatal(1, "S00-02 timeout");
    end

    initial begin
        rst_n = 1'b1;
        awaddr = 5'h08;
        wdata = 32'hffffffff;
        wstrb = 4'hf;
        awvalid = 1'b1;
        wvalid = 1'b1;
        bready = 1'b0;
        aw_count = 0;
        w_count = 0;
        commit_count = 0;
        b_count = 0;
        expected_addr[0] = 5'h08; expected_data[0] = 32'h12345678; expected_strb[0] = 4'hf;
        expected_addr[1] = 5'h0c; expected_data[1] = 32'h89abcde8; expected_strb[1] = 4'h5;
        expected_addr[2] = 5'h10; expected_data[2] = 32'h76543210; expected_strb[2] = 4'ha;
        expected_addr[3] = 5'h14; expected_data[3] = 32'h11223340; expected_strb[3] = 4'h3;
        expected_addr[4] = 5'h04; expected_data[4] = 32'haabbccdd; expected_strb[4] = 4'hc;

        // Assert between edges to check combinational output gates; release via NBA.
        #2 rst_n = 1'b0;
        #1;
        check_condition({awready, wready, bvalid} === 3'b000, "reset combinational gates block channels immediately");
        repeat (2) begin
            tick;
            check_condition({awready, wready, bvalid} === 3'b000, "reset holds channels inactive");
        end
        @(negedge clk);
        awvalid = 1'b0;
        wvalid = 1'b0;
        @(posedge clk);
        rst_n <= 1'b1;
        #1;
        check_condition({awready, wready, bvalid} === 3'b000, "channels inactive immediately after release");
        tick;
        check_condition({awready, wready, bvalid} === 3'b110, "first active edge enables empty entries");
        check_condition(aw_count == 0 && w_count == 0 && commit_count == 0 && b_count == 0,
                        "no reset-time transaction");
        $display("PASS: reset assertion and immediate release keep AWREADY/WREADY/BVALID low");

        // (a) Both channels on the same edge.
        send_pair(expected_addr[0], expected_data[0], expected_strb[0]);
        complete_response(1);
        $display("PASS: simultaneous AW/W -> exactly 1 commit and 1 B response");

        // (b) AW first. Change invalid bus inputs after the accepted address.
        @(negedge clk);
        awaddr = expected_addr[1];
        awvalid = 1'b1;
        tick;
        @(negedge clk);
        awvalid = 1'b0;
        awaddr = 5'h1c;
        repeat (3) begin
            check_condition({awready, wready, bvalid} === 3'b010, "AW full blocks AW only");
            tick;
            check_condition(aw_count == 2 && w_count == 1 && commit_count == 1,
                            "AW-first wait does not overwrite or commit");
        end
        @(negedge clk);
        awvalid = 1'b0;
        wdata = expected_data[1];
        wstrb = expected_strb[1];
        wvalid = 1'b1;
        tick;
        @(negedge clk);
        wvalid = 1'b0;
        wdata = 32'hdeadbeef;
        wstrb = 4'h0;
        complete_response(2);
        $display("PASS: AW first -> AWREADY=0/WREADY=1 while held; 1 commit and 1 B response");

        // (c) W first. The held data/strobe must survive invalid input changes.
        @(negedge clk);
        wdata = expected_data[2];
        wstrb = expected_strb[2];
        wvalid = 1'b1;
        tick;
        @(negedge clk);
        wvalid = 1'b0;
        wdata = 32'h0badcafe;
        wstrb = 4'h1;
        repeat (3) begin
            check_condition({awready, wready, bvalid} === 3'b100, "W full blocks W only");
            tick;
            check_condition(w_count == 3 && aw_count == 2 && commit_count == 2,
                            "W-first wait does not overwrite or commit");
        end
        @(negedge clk);
        wvalid = 1'b0;
        awaddr = expected_addr[2];
        awvalid = 1'b1;
        tick;
        @(negedge clk);
        awvalid = 1'b0;
        awaddr = 5'h1f;
        complete_response(3);
        $display("PASS: W first -> WREADY=0/AWREADY=1 while held; 1 commit and 1 B response");

        // Consecutive writes: offer write #5 while write #4's B response stalls.
        send_pair(expected_addr[3], expected_data[3], expected_strb[3]);
        while (bvalid !== 1'b1) tick;
        @(negedge clk);
        awaddr = expected_addr[4];
        wdata = expected_data[4];
        wstrb = expected_strb[4];
        awvalid = 1'b1;
        wvalid = 1'b1;
        repeat (4) begin
            tick;
            check_condition({bvalid, bresp, awready, wready} === 5'b10000,
                            "B stall holds BVALID/BRESP and blocks AW/W");
            check_condition(aw_count == 4 && w_count == 4 && commit_count == 4 && b_count == 3,
                            "stalled response neither repeats commit nor accepts next write");
        end
        $display("PASS: BREADY delayed 4 cycles -> stable BVALID/BRESP; AWREADY=WREADY=0");
        // R-01 b-2, pending-response phase: both VALID outputs are nonzero
        // before the pulse, so their zero checks cannot pass vacuously.
        while (rvalid !== 1'b1) tick;
        check_condition(bvalid && rvalid, "short-pulse response phase has both VALID outputs high");
        check_short_reset_pulse;
        $display("PASS: R-01 b-2 response phase: short reset masks BVALID/RVALID without clearing registers");
        @(negedge clk);
        bready = 1'b1;
        tick;
        check_condition(aw_count == 4 && w_count == 4 && b_count == 4,
                        "B handshake edge does not also accept the next AW/W");
        tick;
        check_condition(aw_count == 5 && w_count == 5 && commit_count == 4,
                        "next write accepted only after B handshake, without early commit");
        @(negedge clk);
        awvalid = 1'b0;
        wvalid = 1'b0;
        awaddr = 5'h1f;
        wdata = 32'hdeadbeef;
        wstrb = 4'h0;
        tick;
        tick;
        check_condition(commit_count == 5 && b_count == 5, "consecutive writes each complete once");
        @(negedge clk);
        bready = 1'b0;
        repeat (3) tick;
        check_condition(aw_count == 5 && w_count == 5 && commit_count == 5 && b_count == 5,
                        "no stale hold replay after the final response");
        check_condition({awready, wready, bvalid} === 3'b110, "final state is empty COLLECT");
        $display("PASS: 2 consecutive writes preserve distinct address/data/strobe with no replay");
        $display("PASS: concurrent scale/OKAY reads do not disturb writes; control pulses stay zero");
        $display("PASS: totals AW=%0d W=%0d commit=%0d B=%0d", aw_count, w_count, commit_count, b_count);

        // R-01 b-2, idle phase: exercise all three READY gates from high.
        while (arready !== 1'b1) tick;
        check_condition({awready, wready, arready} === 3'b111,
                        "short-pulse idle phase starts with all three READY outputs high");
        check_short_reset_pulse;
        $display("PASS: R-01 b-2 idle phase: short reset masks READY; registers retained as required by reset contract");

        // R-01 b-1: unlike the short pulse, a reset spanning rising edges
        // must clear the real stored values and pending read response.
        @(negedge clk);
        rst_n = 1'b0;
        repeat (2) begin
            tick;
            check_condition({dut.wr_state_reg, dut.channel_enable_reg,
                dut.aw_hold_reg, dut.w_hold_reg, dut.awaddr_reg, dut.wdata_reg,
                dut.wstrb_reg, dut.cmd_reg, dut.input_addr_reg, dut.weight_addr_reg,
                dut.output_addr_reg, dut.bresp_reg, dut.start_reg, dut.clear_status_reg,
                dut.rvalid_reg, dut.rdata_reg, dut.rresp_reg} === 213'b0,
                            "clock-spanning reset clears every sequential register");
            check_condition({awready, wready, bvalid, arready, rvalid} === 5'b00000,
                            "clock-spanning reset keeps AXI outputs inactive");
        end
        @(posedge clk);
        rst_n <= 1'b1;
        #1;
        check_condition({awready, wready, bvalid, arready, rvalid} === 5'b00000,
                        "startup guard remains inactive immediately after valid reset release");
        tick;
        check_condition({awready, wready, bvalid, arready, rvalid} === 5'b11010,
                        "first active edge enables empty channels without a stale response");
        check_condition({reg_start, reg_clear_status, reg_cmd, reg_input_addr,
                         reg_weight_addr, reg_output_addr} === 130'b0,
                        "valid reset leaves no stale CSR or control pulse");
        $display("PASS: R-01 b-1: clock-spanning reset clears registers and restart guard preserves channel timing");
        $display("PASS: S00-02 ALL CHECKS PASSED");
        $finish;
    end
endmodule
