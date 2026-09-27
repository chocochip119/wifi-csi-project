`timescale 1ns / 1ps

// T-02a: simulation-only, single outstanding burst per direction.
// Compile with xvlog -sv. AXI names intentionally match the M00 master.
module axi4_slave_mem_model #(
    parameter integer DATA_WIDTH = 64,
    parameter integer ADDR_WIDTH = 32,
    parameter integer ID_WIDTH = 1
) (
    input wire clk, resetn,
    input wire [ID_WIDTH-1:0] M_AXI_AWID,
    input wire [ADDR_WIDTH-1:0] M_AXI_AWADDR,
    input wire [7:0] M_AXI_AWLEN,
    input wire [2:0] M_AXI_AWSIZE,
    input wire [1:0] M_AXI_AWBURST,
    input wire M_AXI_AWLOCK,
    input wire [3:0] M_AXI_AWCACHE,
    input wire [2:0] M_AXI_AWPROT,
    input wire [3:0] M_AXI_AWQOS,
    input wire M_AXI_AWVALID,
    output wire M_AXI_AWREADY,
    input wire [DATA_WIDTH-1:0] M_AXI_WDATA,
    input wire [DATA_WIDTH/8-1:0] M_AXI_WSTRB,
    input wire M_AXI_WLAST, M_AXI_WVALID,
    output wire M_AXI_WREADY,
    output reg [ID_WIDTH-1:0] M_AXI_BID,
    output reg [1:0] M_AXI_BRESP,
    output wire M_AXI_BVALID,
    input wire M_AXI_BREADY,
    input wire [ID_WIDTH-1:0] M_AXI_ARID,
    input wire [ADDR_WIDTH-1:0] M_AXI_ARADDR,
    input wire [7:0] M_AXI_ARLEN,
    input wire [2:0] M_AXI_ARSIZE,
    input wire [1:0] M_AXI_ARBURST,
    input wire M_AXI_ARLOCK,
    input wire [3:0] M_AXI_ARCACHE,
    input wire [2:0] M_AXI_ARPROT,
    input wire [3:0] M_AXI_ARQOS,
    input wire M_AXI_ARVALID,
    output wire M_AXI_ARREADY,
    output reg [ID_WIDTH-1:0] M_AXI_RID,
    output reg [DATA_WIDTH-1:0] M_AXI_RDATA,
    output reg [1:0] M_AXI_RRESP,
    output reg M_AXI_RLAST,
    output wire M_AXI_RVALID,
    input wire M_AXI_RREADY
);
    // Public controls. Set at a falling edge, before issuing the next burst.
    // Mode 1: one READY opportunity every gap+1 clocks (gap=0: every clock).
    // Mode 2: independent xorshift32 streams; seed=0 maps to 1.
    integer ar_ready_mode = 0, aw_ready_mode = 0, w_ready_mode = 0;
    integer ar_gap_cycles = 0, aw_gap_cycles = 0, w_gap_cycles = 0;
    reg [31:0] ar_seed = 32'h12345678;
    reg [31:0] aw_seed = 32'h23456789;
    reg [31:0] w_seed = 32'h3456789a;
    integer r_gap_cycles = 0, b_delay_cycles = 0, ddr_latency_cycles = 0;
    bit check_outstanding = 1;
    // AXI allows unbounded stalls: no implicit timeout is a protocol rule.
    // Optional test deadline for C10, or call check_quiescent at test end.
    integer write_timeout_cycles = 0;

    reg [1:0] inject_rresp = 0, inject_bresp = 0;
    integer inject_rresp_beat = 0;
    bit inject_rid = 0, inject_bid = 0;
    integer inject_rlast_mode = 0;
    // Counts are cumulative across reset, increment on first driven fault,
    // not when a request is armed and not on every stalled VALID clock.
    integer rresp_injected = 0, rid_injected = 0, bresp_injected = 0;
    integer bid_injected = 0, rlast_injected = 0, injection_count = 0;
    integer violation_count = 0, expected_violation_count = 0;
    integer last_violation_code = 0, expected_code = 0;

    typedef bit [ADDR_WIDTH-4:0] word_index_t;
    reg [DATA_WIDTH-1:0] memory [word_index_t];
    localparam [63:0] UNWRITTEN = 64'hDEAD_BEEF_BAD0_0001;

    function automatic [DATA_WIDTH-1:0] pattern_word(
        input reg [ADDR_WIDTH-1:0] addr, input reg [31:0] seed);
        // For a fixed seed the low word is injective over byte addresses.
        pattern_word = {seed ^ 32'hA5C3_9E71, addr ^ seed};
    endfunction

    function automatic [DATA_WIDTH-1:0] mem_word(input reg [ADDR_WIDTH-1:0] addr);
        word_index_t key;
        begin
            key = addr >> 3;
            if (memory.exists(key) != 0) mem_word = memory[key];
            else mem_word = UNWRITTEN;
        end
    endfunction

    task automatic mem_fill(input reg [ADDR_WIDTH-1:0] addr,
                            input integer bytes, input reg [31:0] seed);
        integer i;
        begin
            if (addr[2:0] != 0 || bytes < 0 || bytes % 8 != 0)
                $fatal(1, "mem_fill requires an aligned whole-word range");
            for (i = 0; i < bytes; i = i + 8)
                memory[word_index_t'((addr + i) >> 3)] = pattern_word(addr + i, seed);
        end
    endtask

    task automatic mem_compare(input reg [ADDR_WIDTH-1:0] addr,
                               input integer bytes, input reg [31:0] seed,
                               output integer mismatches);
        integer i;
        begin
            if (addr[2:0] != 0 || bytes < 0 || bytes % 8 != 0)
                $fatal(1, "mem_compare requires an aligned whole-word range");
            mismatches = 0;
            for (i = 0; i < bytes; i = i + 8)
                if (mem_word(addr + i) !== pattern_word(addr + i, seed))
                    mismatches = mismatches + 1;
        end
    endtask

    task automatic expect_violation(input integer code);
        begin
            if (expected_code != 0 || code < 1 || code > 12)
                $fatal(1, "invalid/nested expect_violation(%0d)", code);
            expected_code = code;
        end
    endtask

    task automatic protocol_error(input integer code, input string msg);
        begin
            violation_count = violation_count + 1;
            last_violation_code = code;
            if (expected_code == code) begin
                expected_code = 0;
                expected_violation_count = expected_violation_count + 1;
                $display("EXPECTED_VIOLATION: C%0d %s at %0t", code, msg, $time);
            end else begin
                $display("FAIL: protocol C%0d %s at %0t (expected C%0d)",
                         code, msg, $time, expected_code);
                $fatal(1, "unexpected AXI master violation");
            end
        end
    endtask

    function automatic [31:0] next_random(input reg [31:0] value);
        reg [31:0] x;
        begin
            x = value == 0 ? 32'd1 : value;
            x = x ^ (x << 13);
            x = x ^ (x >> 17);
            next_random = x ^ (x << 5);
        end
    endfunction

    function automatic bit ready_slot(input integer mode, gap, cycle_number,
                                       input reg [31:0] seed);
        case (mode)
            0: ready_slot = 1;
            1: ready_slot = (cycle_number % (gap + 1)) == 0;
            2: ready_slot = seed[0];
            default: ready_slot = 0;
        endcase
    endfunction

    reg arready_reg, awready_reg, wready_reg, rvalid_reg, bvalid_reg;
    assign M_AXI_ARREADY = resetn && arready_reg;
    assign M_AXI_AWREADY = resetn && awready_reg;
    assign M_AXI_WREADY = resetn && wready_reg;
    assign M_AXI_RVALID = resetn && rvalid_reg;
    assign M_AXI_BVALID = resetn && bvalid_reg;

    integer cycle_count, rd_beats, rd_index, rd_wait;
    reg [ADDR_WIDTH-1:0] rd_addr, wr_addr;
    bit rd_active, aw_seen, wlast_seen;
    integer wr_beats, w_count, w_committed, w_checked;
    integer wlast_cycle, write_idle_cycles;
    reg [DATA_WIDTH-1:0] w_buffer [0:15];
    reg [DATA_WIDTH/8-1:0] strb_buffer [0:15];
    reg last_buffer [0:15];
    reg [1:0] rd_resp_fault, wr_resp_fault;
    integer rd_fault_beat, rd_last_fault;
    bit rd_id_fault, wr_id_fault, rd_id_counted, rd_last_counted;
    bit ar_stalled, aw_stalled, w_stalled;
    // Include sideband fields in stability checks as well as required fields.
    reg [ADDR_WIDTH+ID_WIDTH+24:0] held_ar, held_aw;
    reg [DATA_WIDTH+DATA_WIDTH/8:0] held_w;
    wire [ADDR_WIDTH+ID_WIDTH+24:0] ar_payload =
        {M_AXI_ARADDR, M_AXI_ARLEN, M_AXI_ARSIZE, M_AXI_ARBURST, M_AXI_ARID,
         M_AXI_ARLOCK, M_AXI_ARCACHE, M_AXI_ARPROT, M_AXI_ARQOS};
    wire [ADDR_WIDTH+ID_WIDTH+24:0] aw_payload =
        {M_AXI_AWADDR, M_AXI_AWLEN, M_AXI_AWSIZE, M_AXI_AWBURST, M_AXI_AWID,
         M_AXI_AWLOCK, M_AXI_AWCACHE, M_AXI_AWPROT, M_AXI_AWQOS};
    wire [DATA_WIDTH+DATA_WIDTH/8:0] w_payload = {M_AXI_WDATA, M_AXI_WSTRB, M_AXI_WLAST};
    wire ar_fire = M_AXI_ARVALID && M_AXI_ARREADY;
    wire aw_fire = M_AXI_AWVALID && M_AXI_AWREADY;
    wire w_fire = M_AXI_WVALID && M_AXI_WREADY;
    wire r_fire = M_AXI_RVALID && M_AXI_RREADY;
    wire b_fire = M_AXI_BVALID && M_AXI_BREADY;
    integer i, lane;
    reg [DATA_WIDTH-1:0] merged_word;
    bit last_value;

    // C4-C7: sampled at address acceptance, independently of memory service.
    task automatic check_address(input bit is_write,
        input reg [ADDR_WIDTH-1:0] addr, input reg [7:0] len,
        input reg [2:0] size, input reg [1:0] burst, input reg [ID_WIDTH-1:0] id);
        string channel;
        begin
            channel = is_write ? "AW" : "AR";
            if (size !== 3'b011 || burst !== 2'b01 || id !== {ID_WIDTH{1'b0}})
                protocol_error(4, {channel, " SIZE/BURST/ID"});
            if ($isunknown(len) || len > 15) protocol_error(5, {channel, " LEN > 15 or X"});
            if ($isunknown(addr) || addr[2:0] !== 3'b000)
                protocol_error(6, {channel, " address must be 8-byte aligned"});
            if (int'(addr[11:0]) + (int'(len) + 1)*8 > 4096)
                protocol_error(7, {channel, " burst crosses 4 KiB"});
        end
    endtask

    // C10: missing data cannot be inferred from silence alone (AXI has no
    // deadline). The caller declares quiescence, or enables the test timeout.
    task automatic check_quiescent;
        begin
            if (aw_seen && w_count != wr_beats)
                protocol_error(10, "test ended with incomplete write beat count");
            else if (w_count != 0 && !aw_seen)
                $fatal(1, "test ended with W data waiting for AW");
            else if (rd_active || aw_seen || rvalid_reg || bvalid_reg)
                $fatal(1, "test ended with an unfinished response");
            if (expected_code != 0) $fatal(1, "armed violation was never observed");
        end
    endtask

    initial begin
        if (DATA_WIDTH != 64 || ADDR_WIDTH != 32 || ID_WIDTH != 1)
            $fatal(1, "T-02a model supports the contracted 64/32/1 configuration");
    end

    // C12: event monitoring catches even a between-edge reset violation.
    // This is a checker, not an asynchronous reset of the model state.
    always @(resetn or M_AXI_ARVALID or M_AXI_AWVALID or M_AXI_WVALID) begin
        // Allow same-time combinational master reset gates to settle first.
        // No simulation time passes; a real between-edge violation is caught.
        #0;
        if (resetn === 1'b0 &&
            (M_AXI_ARVALID === 1'b1 || M_AXI_AWVALID === 1'b1 || M_AXI_WVALID === 1'b1))
            protocol_error(12, "master VALID asserted during reset");
    end

    always @(posedge clk) begin
        if (!resetn) begin
            arready_reg <= 0; awready_reg <= 0; wready_reg <= 0;
            rvalid_reg <= 0; bvalid_reg <= 0;
            M_AXI_RDATA <= 0; M_AXI_RID <= 0; M_AXI_RRESP <= 0; M_AXI_RLAST <= 0;
            M_AXI_BID <= 0; M_AXI_BRESP <= 0;
            cycle_count = 0; rd_active = 0; rd_beats = 0; rd_index = 0; rd_wait = 0;
            aw_seen = 0; wlast_seen = 0; wr_beats = 0;
            w_count = 0; w_committed = 0; w_checked = 0; write_idle_cycles = 0;
            ar_stalled = 0; aw_stalled = 0; w_stalled = 0;
            inject_rresp = 0; inject_rresp_beat = 0; inject_rid = 0; inject_rlast_mode = 0;
            inject_bresp = 0; inject_bid = 0;
            // RAM, control settings, seeds and cumulative evidence survive reset.
            if (expected_code != 0) $fatal(1, "reset before expected violation was observed");
        end else begin
            cycle_count = cycle_count + 1;
            // C1/C2/C3: retain payload AND VALID until handshake, including
            // the edge on which READY finally rises.
            if (ar_stalled && (M_AXI_ARVALID !== 1'b1 || ar_payload !== held_ar))
                protocol_error(1, "AR payload/VALID changed while stalled");
            if (aw_stalled && (M_AXI_AWVALID !== 1'b1 || aw_payload !== held_aw))
                protocol_error(2, "AW payload/VALID changed while stalled");
            if (w_stalled && (M_AXI_WVALID !== 1'b1 || w_payload !== held_w))
                protocol_error(3, "W payload/VALID changed while stalled");
            ar_stalled = M_AXI_ARVALID && !M_AXI_ARREADY; held_ar = ar_payload;
            aw_stalled = M_AXI_AWVALID && !M_AXI_AWREADY; held_aw = aw_payload;
            w_stalled = M_AXI_WVALID && !M_AXI_WREADY; held_w = w_payload;

            // C11: project contract forbids offering another address before
            // the prior response completes. Disable check to permit offering
            // early; READY still limits this model to one serviced burst.
            if (check_outstanding && rd_active && !(r_fire && rd_index == rd_beats-1) && M_AXI_ARVALID)
                protocol_error(11, "second AR before prior read completion");
            if (check_outstanding && aw_seen && !b_fire && M_AXI_AWVALID)
                protocol_error(11, "second AW before prior B completion");

            if (r_fire) begin
                rvalid_reg <= 0;
                if (rd_index == rd_beats-1) rd_active = 0;
                else begin rd_index = rd_index + 1; rd_wait = r_gap_cycles; end
            end
            if (b_fire) begin
                bvalid_reg <= 0; aw_seen = 0; wlast_seen = 0;
                w_count = 0; w_committed = 0; w_checked = 0;
            end
            if (ar_fire) begin
                check_address(0, M_AXI_ARADDR, M_AXI_ARLEN, M_AXI_ARSIZE, M_AXI_ARBURST, M_AXI_ARID);
                rd_active = 1; rd_addr = M_AXI_ARADDR;
                rd_beats = int'(M_AXI_ARLEN) + 1; rd_index = 0; rd_wait = ddr_latency_cycles;
                rd_resp_fault = inject_rresp; rd_fault_beat = inject_rresp_beat;
                rd_id_fault = inject_rid; rd_last_fault = inject_rlast_mode;
                rd_id_counted = 0; rd_last_counted = 0;
                if (rd_resp_fault != 0 && (rd_fault_beat < 0 || rd_fault_beat >= rd_beats))
                    $fatal(1, "RRESP injection beat outside burst");
                if (rd_last_fault < 0 || rd_last_fault > 2 || (rd_last_fault == 1 && rd_beats < 2))
                    $fatal(1, "invalid RLAST injection (early requires >=2 beats)");
                inject_rresp = 0; inject_rresp_beat = 0; inject_rid = 0; inject_rlast_mode = 0;
            end
            if (rd_active && (!rvalid_reg || r_fire)) begin
                if (rd_wait > 0) rd_wait = rd_wait - 1;
                else begin
                    rvalid_reg <= 1;
                    M_AXI_RDATA <= mem_word(rd_addr + rd_index*8);
                    M_AXI_RID <= rd_id_fault ? {{(ID_WIDTH-1){1'b0}}, 1'b1} : {ID_WIDTH{1'b0}};
                    M_AXI_RRESP <= (rd_index == rd_fault_beat) ? rd_resp_fault : 2'b00;
                    last_value = rd_index == rd_beats-1;
                    if (rd_last_fault == 1) last_value = rd_index == rd_beats-2;
                    if (rd_last_fault == 2) last_value = 0;
                    M_AXI_RLAST <= last_value;
                    if (rd_resp_fault != 0 && rd_index == rd_fault_beat) begin
                        rresp_injected = rresp_injected + 1; injection_count = injection_count + 1;
                    end
                    if (rd_id_fault && !rd_id_counted) begin
                        rd_id_counted = 1; rid_injected = rid_injected + 1; injection_count = injection_count + 1;
                    end
                    if (last_value != (rd_index == rd_beats-1) && !rd_last_counted) begin
                        rd_last_counted = 1; rlast_injected = rlast_injected + 1; injection_count = injection_count + 1;
                    end
                end
            end

            if (aw_fire) begin
                check_address(1, M_AXI_AWADDR, M_AXI_AWLEN, M_AXI_AWSIZE, M_AXI_AWBURST, M_AXI_AWID);
                aw_seen = 1; wr_addr = M_AXI_AWADDR; wr_beats = int'(M_AXI_AWLEN) + 1;
                wr_resp_fault = inject_bresp; wr_id_fault = inject_bid;
                inject_bresp = 0; inject_bid = 0;
            end
            if (w_fire) begin
                // C8: every accepted W beat, even before AW.
                if (M_AXI_WSTRB !== {DATA_WIDTH/8{1'b1}}) protocol_error(8, "WSTRB is not FF");
                if (w_count >= 16) protocol_error(10, "more than 16 buffered W beats");
                else begin
                    w_buffer[w_count] = M_AXI_WDATA;
                    strb_buffer[w_count] = M_AXI_WSTRB;
                    last_buffer[w_count] = M_AXI_WLAST;
                    w_count = w_count + 1;
                end
                if (M_AXI_WLAST) begin wlast_seen = 1; wlast_cycle = cycle_count; end
            end
            if (aw_seen) begin
                // C10 before C9 ensures an extra beat has one primary diagnosis.
                if (w_count > wr_beats) begin
                    if (aw_fire || w_fire) protocol_error(10, "actual W count exceeds AWLEN+1");
                end
                // C9 also validates beats buffered BEFORE address acceptance.
                else begin
                    for (i = w_checked; i < w_count; i = i + 1)
                        if (last_buffer[i] !== (i == wr_beats-1))
                            protocol_error(9, "WLAST position disagrees with AWLEN");
                end
                w_checked = w_count;
                for (i = w_committed; i < w_count; i = i + 1) begin
                    merged_word = mem_word(wr_addr + i*8);
                    for (lane = 0; lane < DATA_WIDTH/8; lane = lane + 1)
                        if (strb_buffer[i][lane]) merged_word[lane*8 +: 8] = w_buffer[i][lane*8 +: 8];
                    memory[word_index_t'((wr_addr + i*8) >> 3)] = merged_word;
                end
                w_committed = w_count;
            end
            if (aw_seen && w_count < wr_beats && !w_fire) write_idle_cycles = write_idle_cycles + 1;
            else write_idle_cycles = 0;
            // C10 optional liveness deadline, explicitly not an AXI timing rule.
            if (write_timeout_cycles > 0 && write_idle_cycles == write_timeout_cycles)
                protocol_error(10, "test write deadline reached with missing W beats");
            // A 17th offered W cannot fit the contractual 16-beat buffer.
            if (!w_fire && M_AXI_WVALID && w_count >= 16)
                protocol_error(10, "extra W offered beyond full burst buffer");
            if (aw_seen && wlast_seen && w_count == wr_beats && !bvalid_reg) begin
                // Delay is measured from WLAST, even when AW arrives later.
                // AW remains an independent prerequisite for any B response.
                if (cycle_count >= wlast_cycle + b_delay_cycles) begin
                    bvalid_reg <= 1;
                    M_AXI_BRESP <= wr_resp_fault;
                    M_AXI_BID <= wr_id_fault ? {{(ID_WIDTH-1){1'b0}}, 1'b1} : {ID_WIDTH{1'b0}};
                    if (wr_resp_fault != 0) begin bresp_injected = bresp_injected + 1; injection_count = injection_count + 1; end
                    if (wr_id_fault) begin bid_injected = bid_injected + 1; injection_count = injection_count + 1; end
                end
            end

            // NBA output updates let the master sample this edge's old READY.
            if (ar_ready_mode == 2) ar_seed = next_random(ar_seed);
            if (aw_ready_mode == 2) aw_seed = next_random(aw_seed);
            if (w_ready_mode == 2) w_seed = next_random(w_seed);
            arready_reg <= !rd_active && ready_slot(ar_ready_mode, ar_gap_cycles, cycle_count, ar_seed);
            awready_reg <= !aw_seen && ready_slot(aw_ready_mode, aw_gap_cycles, cycle_count, aw_seed);
            wready_reg <= !bvalid_reg && w_count < 16 &&
                          ready_slot(w_ready_mode, w_gap_cycles, cycle_count, w_seed);
        end
    end
endmodule
