`timescale 1 ns / 1 ps

// S00-03 register regression, adapted to the completed S00-05 CSR policy.
// Verifies four RW CSRs, byte preservation, ignored writes, and confirmed aliases.
// Rejection and active CONTROL pulse cases are covered by tb_s00_axi_ctrl.
// Use xvlog -sv for this testbench. Expected words below are explicit test data.
module tb_s00_axi_regs;
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

    reg [4:0] rw_addr [0:3];
    reg [31:0] expected_regs [0:3];
    reg [7:0] base_low, written_low, x_low;
    integer index;
    integer write_count, commit_count, b_count;

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
        // Accepted register writes require idle; rejection has a separate TB.
        .status_busy(1'b0),
        .status_done(1'b1),
        .status_error(4'hf),
        .cfg_ok(1'b1),
        .output_scale_bits(32'h3f800000),
        .S_AXI_ACLK(clk),
        .S_AXI_ARESETN(rst_n),
        .S_AXI_AWADDR(awaddr),
        .S_AXI_AWPROT(3'b000),
        .S_AXI_AWVALID(awvalid),
        .S_AXI_AWREADY(awready),
        .S_AXI_WDATA(wdata),
        .S_AXI_WSTRB(wstrb),
        .S_AXI_WVALID(wvalid),
        .S_AXI_WREADY(wready),
        .S_AXI_BRESP(bresp),
        .S_AXI_BVALID(bvalid),
        .S_AXI_BREADY(bready),
        .S_AXI_ARADDR(5'h04),
        .S_AXI_ARPROT(3'b000),
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
                $fatal(1, "S00-03 test failed");
            end
        end
    endtask

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task check_regs;
        input [127:0] expected;
        begin
            if ({reg_cmd, reg_input_addr, reg_weight_addr, reg_output_addr} !== expected) begin
                $display("FAIL: CSR values at %0t: got=%032h expected=%032h", $time,
                         {reg_cmd, reg_input_addr, reg_weight_addr, reg_output_addr}, expected);
                $fatal(1, "S00-03 register mismatch");
            end
        end
    endtask

    // Each call checks all four registers before/after commit and after B.
    // It returns just after B acceptance so another call can issue immediately.
    task write_expect;
        input [4:0] address_value;
        input [31:0] data_value;
        input [3:0] strobe_value;
        input [127:0] expected_after;
        reg [127:0] expected_before;
        begin
            expected_before = {expected_regs[0], expected_regs[1], expected_regs[2], expected_regs[3]};
            @(negedge clk);
            check_regs(expected_before);
            check_condition({awready, wready, bvalid} === 3'b110, "empty COLLECT before write");
            awaddr = address_value;
            wdata = data_value;
            wstrb = strobe_value;
            awvalid = 1'b1;
            wvalid = 1'b1;
            bready = 1'b0;
            tick;
            check_regs(expected_before);
            check_condition(bvalid === 1'b0, "no B response at AW/W capture edge");
            @(negedge clk);
            awvalid = 1'b0;
            wvalid = 1'b0;
            // Poison unaccepted bus inputs; CSR commit must use the held values.
            awaddr = 5'h08;
            wdata = 32'hdeadbeef;
            wstrb = 4'hf;
            tick;
            check_regs(expected_after);
            check_condition({bvalid, bresp} === 3'b100, "commit returns OKAY");
            @(negedge clk);
            bready = 1'b1;
            tick;
            check_regs(expected_after);
            write_count = write_count + 1;
            check_condition(commit_count == write_count && b_count == write_count,
                            "one commit and one B handshake per write");
            {expected_regs[0], expected_regs[1], expected_regs[2], expected_regs[3]} = expected_after;
        end
    endtask

    // Only the selected word's expected result changes. The three other words
    // come from the previously checked state, independently of the RTL decoder.
    task write_selected;
        input integer selected;
        input [4:0] address_value;
        input [31:0] data_value;
        input [3:0] strobe_value;
        input [31:0] expected_word;
        reg [127:0] expected_after;
        begin
            expected_after = {expected_regs[0], expected_regs[1], expected_regs[2], expected_regs[3]};
            expected_after[127 - 32*selected -: 32] = expected_word;
            write_expect(address_value, data_value, strobe_value, expected_after);
        end
    endtask

    task apply_reset;
        begin
            awvalid = 1'b0;
            wvalid = 1'b0;
            bready = 1'b0;
            #2 rst_n = 1'b0;
            #1;
            tick;
            // Synchronous reset takes effect at the rising edge (R-01).
            check_regs(128'b0);
            @(posedge clk);
            rst_n <= 1'b1;
            #1;
            check_regs(128'b0);
            check_condition({awready, wready, bvalid} === 3'b000, "inactive immediately after reset release");
            tick;
            check_regs(128'b0);
            expected_regs[0] = 32'b0;
            expected_regs[1] = 32'b0;
            expected_regs[2] = 32'b0;
            expected_regs[3] = 32'b0;
        end
    endtask

    // Pre-NBA sampling counts the actual commit/response edges.
    always @(posedge clk) begin
        if (rst_n) begin
            check_condition({reg_start, reg_clear_status} === 2'b00,
                            "these writes request no control pulses");
            check_condition(!rvalid || (rdata === 32'h000000fe && rresp === 2'b00),
                            "concurrent STATUS reads return 0xFE/OKAY and do not disturb writes");
            check_condition(bresp === 2'b00, "these idle aligned writes return OKAY");
            if (dut.commit_valid) commit_count = commit_count + 1;
            if (bvalid && bready) b_count = b_count + 1;
        end
    end

    initial begin
        #20000;
        $display("FAIL: S00-03 watchdog timeout");
        $fatal(1, "S00-03 timeout");
    end

    initial begin
        rst_n = 1'b1;
        awaddr = 5'b0;
        awvalid = 1'b0;
        wdata = 32'b0;
        wstrb = 4'b0;
        wvalid = 1'b0;
        bready = 1'b0;
        write_count = 0;
        commit_count = 0;
        b_count = 0;
        rw_addr[0] = 5'h08;
        rw_addr[1] = 5'h0c;
        rw_addr[2] = 5'h10;
        rw_addr[3] = 5'h14;
        apply_reset;
        $display("PASS: reset clears COMMAND/INPUT_ADDR/WEIGHT_ADDR/OUTPUT_ADDR");

        // Full-width COMMAND is preserved, including values other than 0/1.
        // DDR values now meet INPUT/WEIGHT 8-byte and OUTPUT 32-byte alignment.
        write_selected(0, 5'h08, 32'h89abcdef, 4'hf, 32'h89abcdef);
        write_selected(1, 5'h0c, 32'h13579bd8, 4'hf, 32'h13579bd8);
        write_selected(2, 5'h10, 32'h2468ace0, 4'hf, 32'h2468ace0);
        write_selected(3, 5'h14, 32'hfedcba80, 4'hf, 32'hfedcba80);
        $display("PASS: full writes update only the selected CSR and preserve all 32 COMMAND bits");

        for (index = 0; index < 4; index = index + 1) begin
            // Arbitrary low-byte patterns are confined to COMMAND. DDR tests
            // keep aligned low bytes while exercising the same four byte lanes.
            base_low    = (index == 0) ? 8'h44 : 8'h40;
            written_low = (index == 0) ? 8'haa : 8'ha0;
            x_low       = (index == 0) ? 8'h5a : 8'h60;
            write_selected(index, rw_addr[index], {24'h112233, base_low}, 4'hf, {24'h112233, base_low});
            write_selected(index, rw_addr[index], {24'hdeadbe, written_low}, 4'h1, {24'h112233, written_low});
            write_selected(index, rw_addr[index], 32'hcafebb99, 4'h2, {24'h1122bb, written_low});
            write_selected(index, rw_addr[index], 32'h77cc8899, 4'h4, {24'h11ccbb, written_low});
            write_selected(index, rw_addr[index], 32'hdd667788, 4'h8, {24'hddccbb, written_low});
            $display("PASS: offset 0x%02h single-lane strobes 1/2/4/8 preserve other lanes and CSRs", rw_addr[index]);
            write_selected(index, rw_addr[index], 32'h10203040, 4'h6, {24'hdd2030, written_low});
            write_selected(index, rw_addr[index], 32'ha1b2c3d4, 4'hc, {24'ha1b230, written_low});
            $display("PASS: offset 0x%02h combined strobes 6/C preserve unselected bytes", rw_addr[index]);
            // D05: zero strobe in idle preserves the aligned current value.
            write_selected(index, rw_addr[index], 32'hffffffff, 4'h0, {24'ha1b230, written_low});
            $display("PASS: offset 0x%02h idle zero strobe changes no CSR and returns OKAY", rw_addr[index]);
            // Unknown values are confined to disabled lanes; none may propagate.
            write_selected(index, rw_addr[index], {24'hxxxxxx, x_low}, 4'h1, {24'ha1b230, x_low});
            $display("PASS: offset 0x%02h disabled WDATA lanes are ignored, including X values", rw_addr[index]);
        end

        write_expect(5'h00, 32'hfffffffc, 4'hf,
                     {expected_regs[0], expected_regs[1], expected_regs[2], expected_regs[3]});
        $display("PASS: CONTROL reserved bits are ignored; START/CLEAR pulses stay zero");
        write_expect(5'h04, 32'hffffffff, 4'hf,
                     {expected_regs[0], expected_regs[1], expected_regs[2], expected_regs[3]});
        write_expect(5'h18, 32'hffffffff, 4'hf,
                     {expected_regs[0], expected_regs[1], expected_regs[2], expected_regs[3]});
        write_expect(5'h1c, 32'hffffffff, 4'hf,
                     {expected_regs[0], expected_regs[1], expected_regs[2], expected_regs[3]});
        $display("PASS: writes to 0x00/0x04/0x18/0x1C preserve every CSR and return OKAY");

        // D04(a): the CSR access address low two bits remain ignored.
        write_selected(1, 5'h0c, 32'h01020308, 4'hf, 32'h01020308);
        write_selected(1, 5'h0e, 32'h89abcde8, 4'hf, 32'h89abcde8);
        write_selected(1, 5'h0c, 32'h89abcde8, 4'hf, 32'h89abcde8);
        $display("PASS: 0x0C and 0x0E select the same INPUT_ADDR (D04 confirmed)");

        // The second AW/W pair is issued at the first available edge after B.
        write_selected(2, 5'h10, 32'h55aa6698, 4'hf, 32'h55aa6698);
        write_selected(3, 5'h14, 32'h1234abc0, 4'hf, 32'h1234abc0);
        repeat (3) tick;
        check_regs({expected_regs[0], expected_regs[1], expected_regs[2], expected_regs[3]});
        check_condition(write_count == 49 && commit_count == 49 && b_count == 49,
                        "49 writes complete once with no stale replay");
        $display("PASS: consecutive writes preserve distinct destinations/data; no pre-commit updates or replay");

        apply_reset;
        $display("PASS: reset also clears all four previously nonzero CSRs");
        $display("PASS: totals writes=%0d commit=%0d B=%0d", write_count, commit_count, b_count);
        $display("PASS: S00-03 ALL REGISTER CHECKS PASSED");
        $finish;
    end
endmodule
