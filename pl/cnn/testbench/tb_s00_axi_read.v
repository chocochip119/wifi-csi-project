`timescale 1 ns / 1 ps

// S00-04 read regression, adapted to the completed S00-05 CSR policy.
// Checks the read mux, AR snapshots, R stalls, and independent read/write paths.
// Write rejection/control pulses have a separate TB. Compile with xvlog -sv.
module tb_s00_axi_read;
    reg clk, rst_n;
    reg [4:0] awaddr, araddr;
    reg awvalid, wvalid, bready, arvalid, rready;
    reg [31:0] wdata;
    reg [3:0] wstrb;
    wire awready, wready, bvalid, arready, rvalid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;
    reg status_busy, status_done, cfg_ok;
    reg [3:0] status_error;
    reg [31:0] output_scale_bits;
    wire reg_start, reg_clear_status;
    wire [31:0] reg_cmd, reg_input_addr, reg_weight_addr, reg_output_addr;

    integer ar_count, r_count, commit_count, b_count;
    integer error_index, cfg_index, flags_index;
    integer before_ar, before_r;
    reg [3:0] error_cases [0:2];
    reg [31:0] expected_status;
    reg previous_stall;
    reg [31:0] stalled_data;
    reg [1:0] stalled_resp;

    pose_cnn_v1_0_S00_AXI #(
        .C_S_AXI_DATA_WIDTH(32),
        .C_S_AXI_ADDR_WIDTH(5)
    ) dut (
        .reg_start(reg_start), .reg_clear_status(reg_clear_status),
        .reg_cmd(reg_cmd), .reg_input_addr(reg_input_addr),
        .reg_weight_addr(reg_weight_addr), .reg_output_addr(reg_output_addr),
        .status_busy(status_busy), .status_done(status_done),
        .status_error(status_error), .cfg_ok(cfg_ok),
        .output_scale_bits(output_scale_bits),
        .S_AXI_ACLK(clk), .S_AXI_ARESETN(rst_n),
        .S_AXI_AWADDR(awaddr), .S_AXI_AWPROT(3'b101),
        .S_AXI_AWVALID(awvalid), .S_AXI_AWREADY(awready),
        .S_AXI_WDATA(wdata), .S_AXI_WSTRB(wstrb),
        .S_AXI_WVALID(wvalid), .S_AXI_WREADY(wready),
        .S_AXI_BRESP(bresp), .S_AXI_BVALID(bvalid), .S_AXI_BREADY(bready),
        .S_AXI_ARADDR(araddr), .S_AXI_ARPROT(3'b111),
        .S_AXI_ARVALID(arvalid), .S_AXI_ARREADY(arready),
        .S_AXI_RDATA(rdata), .S_AXI_RRESP(rresp),
        .S_AXI_RVALID(rvalid), .S_AXI_RREADY(rready)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task check_condition;
        input condition;
        input [8*120-1:0] message;
        begin
            if (condition !== 1'b1) begin
                $display("FAIL: %0s at %0t", message, $time);
                $fatal(1, "S00-04 test failed");
            end
        end
    endtask

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task check_response;
        input [31:0] expected_data;
        input [1:0] expected_resp;
        begin
            if ({rvalid, rdata, rresp} !== {1'b1, expected_data, expected_resp}) begin
                $display("FAIL: R at %0t: valid=%b data=%08h resp=%b expected=%08h/%b",
                         $time, rvalid, rdata, rresp, expected_data, expected_resp);
                $fatal(1, "S00-04 response mismatch");
            end
            check_condition(arready === 1'b0, "pending R blocks another AR");
        end
    endtask

    // Returns with a pending response and ARVALID low. Live address is poisoned.
    task capture_read;
        input [4:0] address_value;
        input [31:0] expected_data;
        input [1:0] expected_resp;
        begin
            @(negedge clk);
            check_condition({arready, rvalid} === 2'b10, "read slot initially empty");
            araddr = address_value;
            arvalid = 1'b1;
            rready = 1'b0;
            tick;
            check_response(expected_data, expected_resp);
            @(negedge clk);
            arvalid = 1'b0;
            araddr = 5'h1c;
        end
    endtask

    task finish_read;
        input [31:0] expected_data;
        input [1:0] expected_resp;
        begin
            @(negedge clk);
            check_response(expected_data, expected_resp);
            rready = 1'b1;
            tick;
            check_condition({arready, rvalid} === 2'b10, "R handshake frees read slot");
            @(negedge clk);
            rready = 1'b0;
        end
    endtask

    task read_expect;
        input [4:0] address_value;
        input [31:0] expected_data;
        input [1:0] expected_resp;
        begin
            capture_read(address_value, expected_data, expected_resp);
            finish_read(expected_data, expected_resp);
        end
    endtask

    // Returns after commit, with BREADY=0 and one pending B response.
    task start_write;
        input [4:0] address_value;
        input [31:0] data_value;
        begin
            @(negedge clk);
            check_condition({awready, wready, bvalid} === 3'b110, "write entries initially empty");
            awaddr = address_value;
            wdata = data_value;
            wstrb = 4'hf;
            awvalid = 1'b1;
            wvalid = 1'b1;
            bready = 1'b0;
            tick;
            @(negedge clk);
            awvalid = 1'b0;
            wvalid = 1'b0;
            awaddr = 5'h1c;
            wdata = 32'hdeadbeef;
            tick;
            check_condition({bvalid, bresp} === 3'b100, "write committed with OKAY");
        end
    endtask

    task finish_write;
        begin
            @(negedge clk);
            check_condition({bvalid, bresp} === 3'b100, "pending B remains OKAY");
            bready = 1'b1;
            tick;
            check_condition(bvalid === 1'b0, "B handshake completes write");
            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    task write_word;
        input [4:0] address_value;
        input [31:0] data_value;
        begin
            start_write(address_value, data_value);
            finish_write;
        end
    endtask

    // Sample before NBA: count actual handshakes, not next-cycle READY values.
    always @(posedge clk) begin
        if (!rst_n) begin
            previous_stall = 1'b0;
            stalled_data = 32'b0;
            stalled_resp = 2'b00;
        end else begin
            check_condition({reg_start, reg_clear_status} === 2'b00,
                            "these non-CONTROL writes produce no pulses");
            check_condition(bresp === 2'b00, "these idle aligned writes return OKAY");
            if (rvalid) check_condition(arready === 1'b0, "no AR even on R handshake edge");
            if (previous_stall) check_response(stalled_data, stalled_resp);
            previous_stall = rvalid && !rready;
            stalled_data = rdata;
            stalled_resp = rresp;
            if (arvalid && arready) begin
                check_condition(ar_count == r_count, "at most one outstanding read");
                ar_count = ar_count + 1;
            end
            if (rvalid && rready) begin
                check_condition(ar_count == r_count + 1, "one accepted AR per R response");
                r_count = r_count + 1;
            end
            if (dut.commit_valid) commit_count = commit_count + 1;
            if (bvalid && bready) b_count = b_count + 1;
        end
    end

    initial begin
        #20000;
        $display("FAIL: S00-04 watchdog timeout");
        $fatal(1, "S00-04 timeout");
    end

    initial begin
        rst_n = 1'b1;
        awaddr = 5'b0; awvalid = 1'b0;
        wdata = 32'b0; wstrb = 4'b0; wvalid = 1'b0; bready = 1'b0;
        araddr = 5'h18; arvalid = 1'b1; rready = 1'b0;
        status_busy = 1'b1; status_done = 1'b1; status_error = 4'hf;
        cfg_ok = 1'b1; output_scale_bits = 32'h3f800000;
        ar_count = 0; r_count = 0; commit_count = 0; b_count = 0;
        previous_stall = 1'b0;
        error_cases[0] = 4'h0; error_cases[1] = 4'h5; error_cases[2] = 4'hf;

        // Assert between edges; release synchronously through NBA.
        #2 rst_n = 1'b0;
        #1;
        check_condition({arready, rvalid} === 2'b00, "asynchronous reset blocks read channel");
        repeat (2) begin
            tick;
            check_condition({arready, rvalid} === 2'b00, "read channel stays inactive during reset");
        end
        @(posedge clk);
        rst_n <= 1'b1;
        #1;
        check_condition({arready, rvalid} === 2'b00, "immediate release still blocks read channel");
        @(negedge clk);
        arvalid = 1'b0;
        tick;
        check_condition({arready, rvalid} === 2'b10, "startup guard enables empty read slot");
        check_condition(ar_count == 0 && r_count == 0, "reset accepted no read");
        $display("PASS: reset assertion and immediate release keep ARREADY/RVALID low");

        @(negedge clk);
        status_busy = 1'b0;
        write_word(5'h08, 32'h12345678);
        write_word(5'h0c, 32'h10203040);
        write_word(5'h10, 32'h55667788);
        write_word(5'h14, 32'h90abcde0);
        @(negedge clk);
        status_busy = 1'b1;
        read_expect(5'h00, 32'h00000000, 2'b00);
        read_expect(5'h04, 32'h000000ff, 2'b00);
        read_expect(5'h08, 32'h12345678, 2'b00);
        read_expect(5'h0c, 32'h10203040, 2'b00);
        read_expect(5'h10, 32'h55667788, 2'b00);
        read_expect(5'h14, 32'h90abcde0, 2'b00);
        read_expect(5'h18, 32'h3f800000, 2'b00);
        read_expect(5'h1c, 32'h00000000, 2'b00);
        $display("PASS: all 8 offsets match the read mux; all 4 RW values read back");

        for (error_index = 0; error_index < 3; error_index = error_index + 1) begin
            for (cfg_index = 0; cfg_index < 2; cfg_index = cfg_index + 1) begin
                for (flags_index = 0; flags_index < 4; flags_index = flags_index + 1) begin
                    @(negedge clk);
                    status_error = error_cases[error_index];
                    cfg_ok = cfg_index[0];
                    status_busy = flags_index[0];
                    status_done = flags_index[1];
                    // Independent numeric bit weights, including reserved upper zeros.
                    expected_status = (error_cases[error_index] * 16) + (cfg_index * 8)
                                    + ((error_index == 0) ? 0 : 4) + flags_index;
                    read_expect(5'h04, expected_status, 2'b00);
                end
            end
        end
        $display("PASS: STATUS bit layout in 24 combinations (error=0/5/F, cfg=0/1, busy/done=00/01/10/11)");

        @(negedge clk);
        cfg_ok = 1'b0;
        read_expect(5'h18, 32'h00000000, 2'b10);
        @(negedge clk);
        cfg_ok = 1'b1;
        output_scale_bits = 32'h40200000;
        read_expect(5'h18, 32'h40200000, 2'b00);
        $display("PASS: scale returns zero/SLVERR for cfg=0 and scale/OKAY for cfg=1");

        @(negedge clk);
        status_error = 4'h5; cfg_ok = 1'b0; status_done = 1'b1; status_busy = 1'b0;
        capture_read(5'h04, 32'h00000056, 2'b00);
        status_error = 4'hf; cfg_ok = 1'b1; status_done = 1'b0; status_busy = 1'b1;
        output_scale_bits = 32'h40800000;
        repeat (4) begin
            tick;
            check_response(32'h00000056, 2'b00);
            check_condition(arvalid === 1'b0, "ARVALID is low throughout pending R");
        end
        finish_read(32'h00000056, 2'b00);
        $display("PASS: STATUS snapshot survives changed live inputs and 4-cycle R stall with ARVALID low");

        @(negedge clk);
        cfg_ok = 1'b0;
        capture_read(5'h18, 32'h00000000, 2'b10);
        cfg_ok = 1'b1; output_scale_bits = 32'h40a00000;
        repeat (3) begin tick; check_response(32'h00000000, 2'b10); end
        finish_read(32'h00000000, 2'b10);
        capture_read(5'h18, 32'h40a00000, 2'b00);
        cfg_ok = 1'b0; output_scale_bits = 32'h40c00000;
        repeat (3) begin tick; check_response(32'h40a00000, 2'b00); end
        finish_read(32'h40a00000, 2'b00);
        $display("PASS: scale RDATA/RRESP snapshots survive cfg 0->1 and 1->0 during stall");

        // D04 confirmed: byte-offset low bits are ignored for all CSR reads.
        read_expect(5'h0c, 32'h10203040, 2'b00);
        read_expect(5'h0e, 32'h10203040, 2'b00);
        read_expect(5'h04, 32'h000000f5, 2'b00);
        read_expect(5'h07, 32'h000000f5, 2'b00);
        $display("PASS: low address bits ignored (0x0C/0x0E and 0x04/0x07 aliases)");

        @(negedge clk);
        status_busy = 1'b0;
        start_write(5'h08, 32'haabbccdd);
        read_expect(5'h08, 32'haabbccdd, 2'b00);
        check_condition({bvalid, bready, bresp} === 4'b1000, "B still stalled after read completes");
        finish_write;
        $display("PASS: a read completes while the write B response is stalled");

        capture_read(5'h08, 32'haabbccdd, 2'b00);
        write_word(5'h08, 32'h11223344);
        check_response(32'haabbccdd, 2'b00);
        check_condition(reg_cmd === 32'h11223344, "write completed during R stall");
        finish_read(32'haabbccdd, 2'b00);
        read_expect(5'h08, 32'h11223344, 2'b00);
        $display("PASS: a write completes during R stall without changing the pending read snapshot");

        // Set up held AW/W first, then accept AR on exactly the commit edge.
        @(negedge clk);
        awaddr = 5'h08; wdata = 32'hcafebabe; wstrb = 4'hf;
        awvalid = 1'b1; wvalid = 1'b1;
        tick;
        @(negedge clk);
        awvalid = 1'b0; wvalid = 1'b0;
        araddr = 5'h08; arvalid = 1'b1;
        #1;
        check_condition(dut.commit_valid && arvalid && arready, "commit and AR overlap on next edge");
        tick;
        check_response(32'h11223344, 2'b00);
        check_condition(reg_cmd === 32'hcafebabe, "CSR updated on the same edge");
        @(negedge clk);
        arvalid = 1'b0;
        finish_read(32'h11223344, 2'b00);
        finish_write;
        read_expect(5'h08, 32'hcafebabe, 2'b00);
        $display("PASS: simultaneous RW commit and AR acceptance return the pre-update value");

        // Model a synchronous Top/Loader update using NBA on the AR edge.
        @(negedge clk);
        status_busy = 1'b0; status_done = 1'b0; status_error = 4'h0; cfg_ok = 1'b0;
        araddr = 5'h04; arvalid = 1'b1;
        @(posedge clk);
        status_busy <= 1'b1; status_done <= 1'b1; status_error <= 4'h5; cfg_ok <= 1'b1;
        #1;
        check_response(32'h00000000, 2'b00);
        @(negedge clk);
        arvalid = 1'b0;
        finish_read(32'h00000000, 2'b00);
        read_expect(5'h04, 32'h0000005f, 2'b00);
        $display("PASS: same-edge synchronous status update also returns the pre-update snapshot");

        capture_read(5'h0c, 32'h10203040, 2'b00);
        before_ar = ar_count; before_r = r_count;
        araddr = 5'h10; arvalid = 1'b1;
        repeat (2) begin
            tick;
            check_response(32'h10203040, 2'b00);
            check_condition(ar_count == before_ar, "queued second AR not accepted during R stall");
        end
        @(negedge clk);
        rready = 1'b1;
        tick;
        check_condition(ar_count == before_ar && r_count == before_r + 1,
                        "R handshake edge does not accept replacement AR");
        check_condition(rvalid === 1'b0, "first response consumed without replay");
        @(negedge clk);
        rready = 1'b0;
        tick;
        check_condition(ar_count == before_ar + 1, "second AR accepted on following edge");
        check_response(32'h55667788, 2'b00);
        @(negedge clk);
        arvalid = 1'b0; araddr = 5'h1c;
        finish_read(32'h55667788, 2'b00);
        repeat (3) tick;
        check_condition(ar_count == before_ar + 1 && r_count == before_r + 2,
                        "two consecutive reads complete once without stale data or replay");
        check_condition(ar_count == r_count && commit_count == 7 && b_count == 7,
                        "all accepted transactions completed exactly once");
        $display("PASS: consecutive reads stay distinct; no AR acceptance on the R handshake edge");
        $display("PASS: totals AR=%0d R=%0d commit=%0d B=%0d", ar_count, r_count, commit_count, b_count);
        $display("PASS: S00-04 ALL READ CHECKS PASSED");
        $finish;
    end
endmodule
