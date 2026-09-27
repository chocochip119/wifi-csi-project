`timescale 1 ns / 1 ps

// T-06 status regression: LOAD/INFER use short read/Loader/Encoder/FC handshake models.
// Compile with xvlog -sv. Force/release is limited to state recovery and exhaustive selector decoding.
module tb_ctrl_status;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg reg_start = 1'b0, reg_clear_status = 1'b0;
    reg [31:0] reg_cmd = 32'b0;
    reg [31:0] reg_input_addr = 32'b0, reg_weight_addr = 32'b0, reg_output_addr = 32'b0;
    reg cfg_ok = 1'b0;
    wire status_busy, status_done;
    wire [3:0] status_error;
    wire mem_rd_start, mem_rd_ready, mem_wr_start, loader_start, ld_valid;
    wire enc_start, in_we, fc_start, fifo_we;
    wire [31:0] mem_rd_addr, mem_wr_addr;
    wire [19:0] mem_rd_bytes, mem_wr_bytes;
    wire [63:0] mem_wr_data, ld_data, in_wdata, fifo_wdata;
    wire [10:0] in_waddr;
    wire [1:0] fc_sel;
    reg [63:0] unused_inputs = 64'b0;
    reg [127:0] expected_snapshot;
    integer starts_checked = 0;
    integer zero_output_checks = 0;
    integer recovery_checks = 0;
    integer state_index;
    reg [3:0] recovery_state;
    reg [15:0] selector_states_seen=16'b0;


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
        .mem_rd_busy(mock_rd_busy), .mem_rd_data(unused_inputs),
        .mem_rd_valid(1'b0), .mem_rd_ready(mem_rd_ready), .mem_rd_err(1'b0),
        .mem_wr_start(mem_wr_start), .mem_wr_addr(mem_wr_addr), .mem_wr_bytes(mem_wr_bytes),
        .mem_wr_busy(mock_wr_busy), .mem_wr_data(mem_wr_data),
        .mem_wr_ready(mock_wr_ready), .mem_wr_err(1'b0),
        .loader_start(loader_start), .loader_done(mock_loader_done), .loader_err(1'b0),
        .ld_data(ld_data), .ld_valid(ld_valid), .ld_ready(1'b1),
        .enc_start(enc_start), .enc_done(mock_enc_done),
        .in_we(in_we), .in_waddr(in_waddr), .in_wdata(in_wdata),
        .fc_start(fc_start), .fc_done(mock_fc_done), .fc_sel(fc_sel),
        .fifo_we(fifo_we), .fifo_wdata(fifo_wdata), .fifo_full(unused_inputs[11]),
        .pose_data(192'h17161514131211100f0e0d0c0b0a09080706050403020100)
    );

    always #5 clk = ~clk;
    // Unused read/FIFO inputs vary; write now has a completion model.
    always @(negedge clk) unused_inputs <= ~unused_inputs;

    task check;
        input condition;
        input string message;
        begin
            if (condition !== 1'b1) begin
                $display("FAIL: %s at %0t", message, $time);
                $fatal(1, "T-06 standalone mismatch");
            end
        end
    endtask

    task tick;
        begin @(posedge clk); #1; end
    endtask

    task check_status;
        input busy_value, done_value;
        input [3:0] error_value;
        begin
            check({status_busy, status_done, status_error} ===
                  {busy_value, done_value, error_value}, "busy/done/error mismatch");
        end
    endtask

    task check_snapshot;
        begin
            check({u_ctrl.cmd_reg, u_ctrl.input_addr_reg, u_ctrl.weight_addr_reg,
                   u_ctrl.output_addr_reg} === expected_snapshot, "configuration snapshot mismatch");
        end
    endtask

    task begin_run;
        input [31:0] command_value;
        input cfg_value, clear_value;
        begin
            @(negedge clk);
            check(!status_busy, "START scenario begins in IDLE");
            reg_cmd = command_value;
            reg_input_addr = 32'h1e000000;
            reg_weight_addr = 32'h1e020000;
            reg_output_addr = 32'h1e090000;
            cfg_ok = cfg_value;
            reg_start = 1'b1;
            reg_clear_status = clear_value;
            expected_snapshot = {command_value, 32'h1e000000, 32'h1e020000, 32'h1e090000};
            #1;
            check(!status_busy, "START must not raise busy before the sampling edge");
            tick;
            check_status(1'b1, 1'b0, 4'd0);
            check(u_ctrl.state_reg === 4'd1, "START enters DECODE");
            check_snapshot;
            check(u_ctrl.run_error_reg === 4'd0, "START clears internal result before DECODE");
            starts_checked = starts_checked + 1;
        end
    endtask

    task decode_run;
        input [3:0] result_error;
        input decode_cfg, clear_value, busy_start;
        begin
            @(negedge clk);
            reg_start = busy_start;
            reg_clear_status = clear_value;
            // DECODE uses the captured command but the current cfg_ok.
            reg_cmd = 32'hdeadbeef;
            reg_input_addr = 32'h10101010;
            reg_weight_addr = 32'h20202020;
            reg_output_addr = 32'h30303020;
            cfg_ok = decode_cfg;
            #1;
            check_status(1'b1, 1'b0, 4'd0);
            check_snapshot;
            check(u_ctrl.run_error_reg === 4'd0, "DECODE does not record an error before its edge");
            tick;
            if (expected_snapshot[127:96] == 32'd1) begin
                check(u_ctrl.state_reg === 4'd2, "LOAD DECODE enters LD_RD1");
                while (u_ctrl.state_reg != 4'd12) begin
                    check_status(1'b1,1'b0,4'd0); check_snapshot;
                    tick;
                end
                check(mock_commands == 2, "LOAD uses exactly two memory commands");
            end
            if (expected_snapshot[127:96] == 32'd0 && result_error == 0) begin
                check(u_ctrl.state_reg === 4'd5, "INFER DECODE enters IN_RD");
                while (u_ctrl.state_reg != 4'd12) begin
                    check_status(1'b1,1'b0,4'd0); check_snapshot;
                    tick;
                end
            end
            check(u_ctrl.state_reg === 4'd12, "decoded command eventually reaches FINISH");
            check_status(1'b1, 1'b0, 4'd0);
            check_snapshot;
            check(u_ctrl.run_error_reg === result_error, "DECODE evaluates saved cmd and current cfg");
        end
    endtask

    task finish_run;
        input [3:0] result_error;
        input clear_value, busy_start;
        begin
            @(negedge clk);
            reg_start = busy_start;
            reg_clear_status = clear_value;
            // FINISH ignores START and subsequent command/cfg changes.
            reg_cmd = 32'hdeadbeef;
            reg_input_addr = 32'h10101010;
            reg_weight_addr = 32'h20202020;
            reg_output_addr = 32'h30303020;
            cfg_ok = !cfg_ok;
            #1;
            check_status(1'b1, 1'b0, 4'd0);
            check_snapshot;
            check(u_ctrl.run_error_reg === result_error, "CLEAR/input changes preserve pending result");
            tick;
            check(u_ctrl.state_reg === 4'd0, "FINISH enters IDLE");
            check_status(1'b0, result_error == 4'd0, result_error);
            check_snapshot;
            check(u_ctrl.run_error_reg === result_error, "completion preserves pending result");
            @(negedge clk);
            reg_start = 1'b0;
            reg_clear_status = 1'b0;
            repeat (3) begin
                tick;
                check_status(1'b0, result_error == 4'd0, result_error);
                check_snapshot;
            end
        end
    endtask

    task check_recovery;
        input [3:0] injected_state;
        reg [3:0] saved_result;
        reg [4:0] saved_display;
        begin
            saved_result = u_ctrl.run_error_reg;
            saved_display = {status_done, status_error};
            @(negedge clk);
            // Use a module-level force source (avoids task-argument sensitivity
            // warnings). Release before the edge so the DUT's NBA can recover.
            recovery_state = injected_state;
            force u_ctrl.state_reg = recovery_state;
            #1;
            check(u_ctrl.state_reg === injected_state, "requested recovery state is actually injected");
            check(status_busy === 1'b1, "every non-IDLE encoding reports busy");
            check(u_ctrl.state_next === 4'd0, "illegal state selects IDLE");
            release u_ctrl.state_reg;
            tick;
            check(u_ctrl.state_reg === 4'd0, "illegal state recovers on next edge");
            check(status_busy === 1'b0, "recovery lowers busy");
            check({status_done, status_error} === saved_display, "recovery preserves displayed result");
            check(u_ctrl.run_error_reg === saved_result, "recovery preserves internal result");
            check_snapshot;
            recovery_checks = recovery_checks + 1;
        end
    endtask

    task clear_idle;
        reg [3:0] saved_result;
        begin
            saved_result = u_ctrl.run_error_reg;
            @(negedge clk);
            reg_clear_status = 1'b1;
            tick;
            check_status(1'b0, 1'b0, 4'd0);
            check_snapshot;
            check(u_ctrl.run_error_reg === saved_result, "IDLE CLEAR also preserves internal result");
            @(negedge clk);
            reg_clear_status = 1'b0;
            tick;
            check_status(1'b0, 1'b0, 4'd0);
        end
    endtask

    always @(posedge clk) begin
        #2;
        if (u_ctrl.state_reg!=4'd9 && u_ctrl.state_reg!=4'd10)
        check({mem_wr_start, mem_wr_addr, mem_wr_bytes, mem_wr_data} === '0,
              "write outputs stay zero outside FC3/WR, including reset");
        zero_output_checks = zero_output_checks + 1;
    end

    initial begin
        #10000;
        $fatal(1, "T-06 standalone watchdog timeout");
    end

    initial begin
        check($bits(u_ctrl.state_reg) == 4 && $bits(u_ctrl.state_next) == 4,
              "state registers must be four bits");
        check({u_ctrl.IDLE, u_ctrl.DECODE, u_ctrl.LD_RD1, u_ctrl.LD_RD2,
               u_ctrl.LD_WAIT, u_ctrl.IN_RD, u_ctrl.ENC, u_ctrl.FC1,
               u_ctrl.FC2, u_ctrl.FC3, u_ctrl.WR, u_ctrl.ERR_DRAIN, u_ctrl.FINISH} ===
              {4'd0, 4'd1, 4'd2, 4'd3, 4'd4, 4'd5, 4'd6, 4'd7,
               4'd8, 4'd9, 4'd10, 4'd11, 4'd12}, "all thirteen state encodings match target FSM");
        $display("PASS: thirteen named states and four-bit state registers match the target FSM");
        repeat (2) tick;
        expected_snapshot = 128'b0;
        check_status(1'b0, 1'b0, 4'd0);
        check_snapshot;
        check(u_ctrl.run_error_reg === 4'd0, "reset clears pending result");
        // Change reset away from sampling races; state updates only at posedge.
        @(posedge clk); rst_n <= 1'b1;
        tick;
        $display("PASS: reset clears status, snapshots and pending result");

        begin_run(32'd1, 1'b0, 1'b0);
        decode_run(4'd0, 1'b0, 1'b0, 1'b0);
        finish_run(4'd0, 1'b0, 1'b0);
        $display("PASS: LOAD succeeds with cfg=0 after two modeled reads and Loader completion");

        begin_run(32'd0, 1'b1, 1'b0);
        decode_run(4'd0, 1'b1, 1'b0, 1'b0);
        finish_run(4'd0, 1'b0, 1'b0);
        $display("PASS: INFER cfg=1 succeeds; START clears done; live cmd/address changes do not replace snapshots");
        clear_idle;
        $display("PASS: IDLE CLEAR removes sticky done without changing snapshots/internal result");

        begin_run(32'd0, 1'b0, 1'b0);
        decode_run(4'd2, 1'b0, 1'b0, 1'b0);
        finish_run(4'd2, 1'b0, 1'b0);
        $display("PASS: INFER cfg=0 at DECODE reports NO_CFG; cfg changes in FINISH cannot change it");

        begin_run(32'd0, 1'b0, 1'b0);
        decode_run(4'd0, 1'b1, 1'b0, 1'b0);
        finish_run(4'd0, 1'b0, 1'b0);
        $display("PASS: INFER cfg 0 at START -> 1 at DECODE succeeds");
        begin_run(32'd0, 1'b1, 1'b0);
        decode_run(4'd2, 1'b0, 1'b0, 1'b0);
        finish_run(4'd2, 1'b0, 1'b0);
        $display("PASS: INFER cfg 1 at START -> 0 at DECODE reports NO_CFG");

        begin_run(32'd2, 1'b0, 1'b0);
        decode_run(4'd1, 1'b0, 1'b0, 1'b0);
        finish_run(4'd1, 1'b0, 1'b0);
        $display("PASS: cmd=2 reports BAD_CMD; new START clears previous NO_CFG");
        begin_run(32'hffffffff, 1'b1, 1'b0);
        decode_run(4'd1, 1'b1, 1'b0, 1'b0);
        finish_run(4'd1, 1'b0, 1'b0);
        $display("PASS: cmd=FFFFFFFF reports BAD_CMD; consecutive errors are recorded anew");
        begin_run(32'h80000000, 1'b0, 1'b0);
        decode_run(4'd1, 1'b0, 1'b0, 1'b0);
        finish_run(4'd1, 1'b0, 1'b0);
        $display("PASS: cmd=80000000 reports BAD_CMD (full 32-bit decode, independent of cfg)");
        clear_idle;
        $display("PASS: IDLE CLEAR removes sticky error without erasing internal failure");

        begin_run(32'd1, 1'b0, 1'b0);
        decode_run(4'd0, 1'b0, 1'b1, 1'b0);
        finish_run(4'd0, 1'b1, 1'b0);
        $display("PASS: BUSY CLEAR cannot cancel success; completion wins over same-edge CLEAR");
        begin_run(32'd0, 1'b0, 1'b0);
        decode_run(4'd2, 1'b0, 1'b1, 1'b0);
        finish_run(4'd2, 1'b1, 1'b0);
        $display("PASS: BUSY CLEAR preserves NO_CFG; error wins over same-edge CLEAR");

        begin_run(32'd1, 1'b0, 1'b1);
        decode_run(4'd0, 1'b0, 1'b0, 1'b0);
        finish_run(4'd0, 1'b0, 1'b0);
        $display("PASS: IDLE START+CLEAR accepts START and clears old error before new completion");

        begin_run(32'd1, 1'b0, 1'b0);
        decode_run(4'd0, 1'b0, 1'b0, 1'b1);
        finish_run(4'd0, 1'b0, 1'b1);
        $display("PASS: START is ignored in both DECODE and FINISH; success and all four snapshots survive");
        begin_run(32'd2, 1'b1, 1'b0);
        decode_run(4'd1, 1'b1, 1'b1, 1'b1);
        finish_run(4'd1, 1'b1, 1'b1);
        $display("PASS: BUSY START+CLEAR cannot overwrite original BAD_CMD at completion");

        // Pending/displayed BAD_CMD is intentionally nonzero, so a recovery
        // that silently clears results cannot pass these checks.
        for (state_index = 13; state_index <= 15; state_index = state_index + 1)
            check_recovery(state_index[3:0]);
        $display("PASS: all thirteen states implemented; three illegal states recover without changing results/snapshots (%0d checks)", recovery_checks);

        begin_run(32'd2, 1'b0, 1'b0);
        decode_run(4'd1, 1'b0, 1'b0, 1'b0);
        // Assert between edges in FINISH. Synchronous reset must preserve all
        // registers until the next rising edge, then abort without completion.
        #1; rst_n = 1'b0; reg_start = 1'b0;
        #1;
        check_status(1'b1, 1'b0, 4'd0);
        check(u_ctrl.state_reg === 4'd12, "synchronous reset cannot change FINISH between edges");
        check_snapshot;
        check(u_ctrl.run_error_reg === 4'd1, "synchronous reset preserves pending result before edge");
        tick;
        expected_snapshot = 128'b0;
        check_status(1'b0, 1'b0, 4'd0);
        check_snapshot;
        check(u_ctrl.run_error_reg === 4'd0, "synchronous reset aborts pending result at rising edge");
        @(posedge clk); rst_n <= 1'b1;
        repeat (2) tick;
        check_status(1'b0, 1'b0, 4'd0);
        $display("PASS: synchronous reset in FINISH waits for the edge, clears all state, and produces no phantom completion");
        // Exhaustive combinational decode, including the three illegal codes.
        // Hold reset while injecting states so no artificial START is consumed.
        @(negedge clk);rst_n=0;
        for(state_index=0;state_index<16;state_index=state_index+1) begin
            recovery_state=state_index[3:0];
            force u_ctrl.state_reg=recovery_state;
            #1;
            check(u_ctrl.state_reg===recovery_state,"S2 forced state is the observed state");
            check(param_sel_fc===((recovery_state==7)||(recovery_state==8)||(recovery_state==9)) &&
                  lut_sel_fc===param_sel_fc,"S2 current-state selection, including illegal states");
            selector_states_seen[recovery_state]=1'b1;
            $display("PASS: L-07 S2 state=%0d param_sel_fc=%b lut_sel_fc=%b",u_ctrl.state_reg,param_sel_fc,lut_sel_fc);
            release u_ctrl.state_reg;
            tick;
            @(negedge clk);
        end
        rst_n=1;tick;
        check_status(1'b0,1'b0,4'd0);
        check(selector_states_seen===16'hffff,"S2 all sixteen observed state encodings covered");
        $display("PASS: L-07 S2 states=13 illegal_codes=3 FC_selected=7,8,9 all_others=0");
        $display("PASS: unused outputs stayed zero for %0d sampled cycles while unused inputs toggled", zero_output_checks);
        $display("PASS: T-06 ALL CTRL STATUS CHECKS PASSED (%0d START snapshots checked)", starts_checked);
        $finish;
    end
endmodule
