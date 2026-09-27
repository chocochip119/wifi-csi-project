`timescale 1 ns / 1 ps

// T-06 CSR/ctrl integration regression. All commands use AXI4-Lite.
// cfg_ok/scale model Loader-owned levels. No hierarchical drive, force or delay
// extension of ctrl busy is used. LOAD/INFER use short read/Loader/Encoder/FC handshake models.
module tb_csr_ctrl_link;
    reg clk = 1'b0, rst_n = 1'b0;
    reg [4:0] awaddr = 5'b0, araddr = 5'b0;
    reg [31:0] wdata = 32'b0;
    reg [3:0] wstrb = 4'hf;
    reg awvalid = 1'b0, wvalid = 1'b0, arvalid = 1'b0;
    reg bready = 1'b1, rready = 1'b1;
    wire awready, wready, bvalid, arready, rvalid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;
    wire reg_start, reg_clear_status;
    wire [31:0] reg_cmd, reg_input_addr, reg_weight_addr, reg_output_addr;
    wire status_busy, status_done;
    wire [3:0] status_error;
    reg cfg_ok = 1'b0;
    reg [31:0] output_scale_bits = 32'h3f800000;
    wire mem_rd_start, mem_rd_ready, mem_wr_start, loader_start, ld_valid;
    wire enc_start, in_we, fc_start, fifo_we;
    wire [31:0] mem_rd_addr, mem_wr_addr;
    wire [19:0] mem_rd_bytes, mem_wr_bytes;
    wire [63:0] mem_wr_data, ld_data, in_wdata, fifo_wdata;
    wire [10:0] in_waddr;
    wire [1:0] fc_sel;
    reg [31:0] observed;
    integer start_count = 0, busy_cycles = 0, busy_reads = 0;
    integer command_busy_commits = 0;
    integer cycle_count = 0, start_commit_cycle = 0, command_commit_cycle = 0;

    // CSR boundary has six outputs and five status/Loader inputs (11 signals).
    pose_cnn_v1_0_S00_AXI u_csr (
        .reg_start(reg_start), .reg_clear_status(reg_clear_status), .reg_cmd(reg_cmd),
        .reg_input_addr(reg_input_addr), .reg_weight_addr(reg_weight_addr),
        .reg_output_addr(reg_output_addr), .status_busy(status_busy),
        .status_done(status_done), .status_error(status_error),
        .cfg_ok(cfg_ok), .output_scale_bits(output_scale_bits),
        .S_AXI_ACLK(clk), .S_AXI_ARESETN(rst_n),
        .S_AXI_AWADDR(awaddr), .S_AXI_AWPROT(3'b0), .S_AXI_AWVALID(awvalid), .S_AXI_AWREADY(awready),
        .S_AXI_WDATA(wdata), .S_AXI_WSTRB(wstrb), .S_AXI_WVALID(wvalid), .S_AXI_WREADY(wready),
        .S_AXI_BRESP(bresp), .S_AXI_BVALID(bvalid), .S_AXI_BREADY(bready),
        .S_AXI_ARADDR(araddr), .S_AXI_ARPROT(3'b0), .S_AXI_ARVALID(arvalid), .S_AXI_ARREADY(arready),
        .S_AXI_RDATA(rdata), .S_AXI_RRESP(rresp), .S_AXI_RVALID(rvalid), .S_AXI_RREADY(rready)
    );


    // Small handshake-only environment for CSR/status regression. Full data
    // and real-M00 data verification belongs to tb_top_load/tb_top_infer.
    reg mock_rd_busy = 0, mock_loader_done = 0, mock_enc_done = 0, mock_fc_done = 0;
    integer mock_left = 0, mock_commands = 0, mock_done_left = 0, mock_enc_left = 0, mock_fc_left = 0;
    reg mock_wr_busy=0;
    integer mock_wr_left=0;
    wire mock_wr_ready=mock_wr_busy && mock_wr_left>2;
    always @(posedge clk) begin
        if (!rst_n) begin
            mock_rd_busy <= 0; mock_loader_done <= 0; mock_enc_done <= 0; mock_enc_left <= 0; mock_fc_done <= 0; mock_fc_left <= 0;
            mock_left <= 0; mock_commands <= 0; mock_done_left <= 0;
            mock_wr_busy<=0; mock_wr_left<=0;
        end else begin
            mock_loader_done <= 0; mock_enc_done <= 0; mock_fc_done <= 0;
            if (mem_wr_start) begin mock_wr_busy<=1; mock_wr_left<=5; end
            else if (mock_wr_busy) begin
                if (mock_wr_left==0) mock_wr_busy<=0;
                else mock_wr_left<=mock_wr_left-1;
            end
            if (fc_start) mock_fc_left <= 5;
            else if (mock_fc_left != 0) begin
                mock_fc_left <= mock_fc_left-1;
                if (mock_fc_left == 1) mock_fc_done <= 1;
            end
            if (enc_start) mock_enc_left <= 3;
            else if (mock_enc_left != 0) begin
                mock_enc_left <= mock_enc_left-1;
                if (mock_enc_left == 1) mock_enc_done <= 1;
            end
            if (mem_rd_start) begin
                mock_rd_busy <= 1; mock_left <= 2;
                if ((mem_rd_bytes == 11520) || (mem_rd_bytes == 393216)) mock_commands <= 0;
                else if (loader_start) mock_commands <= 1;
                else mock_commands <= mock_commands+1;
            end else if (mock_rd_busy) begin
                if (mock_left == 0) begin
                    mock_rd_busy <= 0;
                    if (mock_commands == 2) mock_done_left <= 2;
                end else mock_left <= mock_left-1;
            end
            if (mock_done_left != 0) begin
                mock_done_left <= mock_done_left-1;
                if (mock_done_left == 1) mock_loader_done <= 1;
            end
        end
    end

    wire param_sel_fc, lut_sel_fc;
    pose_cnn_ctrl u_ctrl (
        .param_sel_fc(param_sel_fc), .lut_sel_fc(lut_sel_fc),
        .clk(clk), .rst_n(rst_n),
        .reg_start(reg_start), .reg_clear_status(reg_clear_status), .reg_cmd(reg_cmd),
        .reg_input_addr(reg_input_addr), .reg_weight_addr(reg_weight_addr),
        .reg_output_addr(reg_output_addr), .status_busy(status_busy),
        .status_done(status_done), .status_error(status_error), .cfg_ok(cfg_ok),
        .mem_rd_start(mem_rd_start), .mem_rd_addr(mem_rd_addr), .mem_rd_bytes(mem_rd_bytes),
        .mem_rd_busy(mock_rd_busy), .mem_rd_data(64'b0), .mem_rd_valid(1'b0),
        .mem_rd_ready(mem_rd_ready), .mem_rd_err(1'b0),
        .mem_wr_start(mem_wr_start), .mem_wr_addr(mem_wr_addr), .mem_wr_bytes(mem_wr_bytes),
        .mem_wr_busy(mock_wr_busy), .mem_wr_data(mem_wr_data), .mem_wr_ready(mock_wr_ready), .mem_wr_err(1'b0),
        .loader_start(loader_start), .loader_done(mock_loader_done), .loader_err(1'b0),
        .ld_data(ld_data), .ld_valid(ld_valid), .ld_ready(1'b1),
        .enc_start(enc_start), .enc_done(mock_enc_done), .in_we(in_we), .in_waddr(in_waddr), .in_wdata(in_wdata),
        .fc_start(fc_start), .fc_done(mock_fc_done), .fc_sel(fc_sel),
        .fifo_we(fifo_we), .fifo_wdata(fifo_wdata), .fifo_full(1'b0), .pose_data(192'b0)
    );

    always #5 clk = ~clk;

    task check;
        input condition;
        input string message;
        begin
            if (condition !== 1'b1) begin
                $display("FAIL: %s at %0t", message, $time);
                $fatal(1, "T-06 CSR/ctrl integration mismatch");
            end
        end
    endtask

    task tick;
        begin @(posedge clk); #1; end
    endtask

    // Returns just after B handshake: a START has now been sampled by ctrl.
    task write_word;
        input [4:0] address_value;
        input [31:0] data_value;
        input [1:0] expected_resp;
        begin
            @(negedge clk);
            check(awready && wready && !bvalid, "write slot is empty");
            awaddr = address_value; wdata = data_value;
            awvalid = 1'b1; wvalid = 1'b1;
            tick;
            @(negedge clk);
            awvalid = 1'b0; wvalid = 1'b0;
            tick;
            check(bvalid && bresp === expected_resp, "expected response at write commit");
            tick;
            check(!bvalid, "B response consumed exactly once");
        end
    endtask

    task read_word;
        input [4:0] address_value;
        input [1:0] expected_resp;
        output [31:0] value;
        begin
            @(negedge clk);
            check(arready, "read slot is empty");
            araddr = address_value; arvalid = 1'b1;
            tick;
            check(rvalid && rresp === expected_resp, "expected read response");
            value = rdata;
            @(negedge clk); arvalid = 1'b0;
            tick;
            check(!rvalid, "R response consumed exactly once");
        end
    endtask

    task read_expect;
        input [4:0] address_value;
        input [31:0] expected;
        reg [31:0] value;
        begin
            read_word(address_value, 2'b00, value);
            check(value === expected, "AXI readback value");
        end
    endtask

    task poll_result;
        input [31:0] expected;
        input require_busy;
        reg [31:0] value;
        reg completed, saw_busy;
        integer polls;
        begin
            completed = 1'b0; saw_busy = 1'b0; polls = 0;
            while (!completed && polls < 32) begin
                read_word(5'h04, 2'b00, value);
                polls = polls + 1;
                $display("TRACE: STATUS poll %0d = 0x%08h", polls, value);
                if (value[0]) begin
                    saw_busy = 1'b1;
                    check(value === (cfg_ok ? 32'h00000009 : 32'h00000001),
                          "START clears previous done/error in the busy snapshot");
                end
                // PS contract: never terminate on done/error without !busy.
                completed = !value[0] && (value[1] || value[2]);
            end
            check(completed, "bounded STATUS polling reaches !busy && (done || error)");
            check(value === expected, "final STATUS including error code and cfg_ok");
            if (require_busy) check(saw_busy, "prompt AXI polling observes DECODE/FINISH busy");
        end
    endtask

    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count = cycle_count + 1;
            if (reg_start) start_count = start_count + 1;
            if (status_busy) busy_cycles = busy_cycles + 1;
            if (arvalid && arready && araddr == 5'h04 && status_busy)
                busy_reads = busy_reads + 1;
            // Observation only; AXI is the only command/configuration driver.
            if (u_csr.commit_valid && u_csr.awaddr_reg[4:2] == 3'd0 && u_csr.wdata_reg[0])
                start_commit_cycle = cycle_count;
            if (u_csr.commit_valid && u_csr.awaddr_reg[4:2] == 3'd2) begin
                command_commit_cycle = cycle_count;
                if (status_busy) command_busy_commits = command_busy_commits + 1;
            end
        end
        #2;
        if (u_ctrl.state_reg!=4'd9 && u_ctrl.state_reg!=4'd10)
        check({mem_wr_start, mem_wr_addr, mem_wr_bytes, mem_wr_data} === '0,
               "write outputs stay zero outside FC3/WR");
    end

    initial begin
        #20000;
        $fatal(1, "T-06 integration watchdog timeout");
    end

    initial begin
        repeat (2) tick;
        @(posedge clk); rst_n <= 1'b1;
        tick;
        read_expect(5'h04, 32'h00000000);
        write_word(5'h0c, 32'h1e000000, 2'b00);
        write_word(5'h10, 32'h1e020000, 2'b00);
        write_word(5'h14, 32'h1e090000, 2'b00);
        read_expect(5'h0c, 32'h1e000000);
        read_expect(5'h10, 32'h1e020000);
        read_expect(5'h14, 32'h1e090000);
        $display("PASS: AXI reset STATUS=0 and three aligned address writes/readbacks");

        write_word(5'h08, 32'd1, 2'b00);
        write_word(5'h00, 32'd1, 2'b00);
        poll_result(32'h00000002, 1'b1);
        read_expect(5'h04, 32'h00000002);
        $display("PASS: AXI COMMAND=1 -> START -> busy snapshot 0x01 -> sticky done 0x02");

        write_word(5'h00, 32'd2, 2'b00);
        read_expect(5'h04, 32'h00000000);
        $display("PASS: AXI CLEAR removes done; STATUS reads have no clear side effect");

        write_word(5'h08, 32'd2, 2'b00);
        write_word(5'h00, 32'd1, 2'b00);
        poll_result(32'h00000014, 1'b1);
        $display("PASS: AXI COMMAND=2 -> START -> BAD_CMD STATUS=0x14 (writes still OKAY)");
        write_word(5'h00, 32'd2, 2'b00);
        read_expect(5'h04, 32'h00000000);
        $display("PASS: AXI CLEAR removes error and error_code");

        write_word(5'h08, 32'd0, 2'b00);
        write_word(5'h00, 32'd1, 2'b00);
        poll_result(32'h00000024, 1'b1);
        $display("PASS: AXI INFER cfg=0 -> NO_CFG STATUS=0x24");
        // Repeat without CLEAR: accepted START itself must remove old error.
        write_word(5'h00, 32'd1, 2'b00);
        poll_result(32'h00000024, 1'b1);
        $display("PASS: AXI repeated failing START clears old error during busy and records new NO_CFG");

        @(negedge clk); cfg_ok = 1'b1;
        read_expect(5'h18, 32'h3f800000);
        write_word(5'h00, 32'd1, 2'b00);
        poll_result(32'h0000000a, 1'b1);
        $display("PASS: AXI INFER cfg=1 -> busy 0x09 -> done 0x0A; Loader scale passes through CSR");
        write_word(5'h00, 32'd3, 2'b00);
        poll_result(32'h0000000a, 1'b1);
        $display("PASS: AXI idle START+CLEAR works with the real ctrl");

        // At START commit E0, busy is 0. E1 consumes B and enters DECODE.
        // Earliest next AW/W is E2, when LOAD enters LD_RD1. At E3 the
        // COMMAND commit sees LOAD busy=1 and records SLVERR. LOAD continues.
        write_word(5'h08, 32'd1, 2'b00);
        write_word(5'h00, 32'd1, 2'b00);
        check(status_busy, "real ctrl busy before issuing fastest next COMMAND");
        check(u_ctrl.state_reg === 4'b0001, "START B handshake coincides with DECODE entry");
        write_word(5'h08, 32'd2, 2'b10);
        check(command_commit_cycle - start_commit_cycle == 3,
               "earliest COMMAND commit is three edges after START commit");
        check(command_busy_commits == 1, "fastest COMMAND commits while LOAD is busy");
        check(status_busy, "LOAD continues while rejected COMMAND response is consumed");
        read_expect(5'h08, 32'd1);
        poll_result(32'h0000000a, 1'b0);
        check(u_ctrl.cmd_reg === 32'd1, "rejected CSR write preserves completed command snapshot");
        $display("PASS: fastest COMMAND commits at START+3 with LOAD busy=1, returns SLVERR and preserves CSR/snapshot");

        write_word(5'h00, 32'd2, 2'b00);
        read_expect(5'h04, 32'h00000008);
        $display("PASS: totals START=%0d busy_cycles=%0d AXI_busy_reads=%0d busy_COMMAND_commits=%0d",
                 start_count, busy_cycles, busy_reads, command_busy_commits);
        // Modeled LOAD=12; INFER=DECODE(1)+IN_RD(4)+ENC(4)+FC1/2/3(18)+WR(7)+FINISH(1)=35.
        check(start_count == 7 && busy_cycles == 100 && busy_reads >= 6,
              "seven STARTs: two 12-cycle LOADs + two 35-cycle INFERs + three 2-cycle errors; busy snapshots observed");
        $display("PASS: T-06 ALL REACHABLE CSR/CTRL LINK CHECKS PASSED");
        $finish;
    end
endmodule
