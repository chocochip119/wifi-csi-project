`timescale 1ns / 1ps

module tb_fc_storage;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg fifo_we = 0, fifo_re = 0;
    reg [63:0] fifo_wdata = 0;
    wire [63:0] fifo_rdata;
    wire fifo_full, fifo_empty;
    reg hidden_we = 0, hidden_wbank = 0, hidden_rbank = 0;
    reg [7:0] hidden_waddr = 0, hidden_wdata = 0;
    reg [4:0] hidden_raddr = 0;
    wire [63:0] hidden_rdata;
    reg pose_we = 0;
    reg [4:0] pose_waddr = 0;
    reg [7:0] pose_wdata = 0;
    wire [191:0] pose_data;
    fc1_weight_fifo u_fifo (.*);
    hidden_buffer u_hidden (.*);
    pose_buffer u_pose (.*);

    // Independent unbounded queue: no mirrored DUT pointers or modulo logic.
    reg [63:0] expected_fifo [$];
    reg [7:0] expected_hidden [0:255];
    reg [191:0] expected_pose;
    integer cycles = 0, checks = 0, pushes = 0, pops = 0;
    integer full_drop = 0, empty_pop = 0, simultaneous = 0;
    integer i, j, bank, size_before, saved_pushes, saved_pops;
    reg [31:0] rng = 32'hF0015128;
    reg [63:0] old_hidden, expected_read;
    reg [191:0] old_pose;
    integer dropped_marker_seen = 0;
    integer saved_checks, saved_cycles, fifo_start_cycle;
    localparam [63:0] DROP_FULL_POP = 64'hDEAD_F011_BAD0_0001;
    localparam [63:0] DROP_FULL_ONLY = 64'hDEAD_F011_BAD0_0002;

    always @(posedge clk) cycles = cycles + 1;
    initial begin
        #2000000;
        $fatal(1, "FAIL: tb_fc_storage timeout cycles=%0d", cycles);
    end
    task check(input bit condition, input string message);
        begin
            checks = checks + 1;
            if (!condition) $fatal(1, "FAIL: cycle=%0d %s", cycles, message);
        end
    endtask
    function automatic [63:0] pattern(input integer index);
        pattern = {32'h51F00000 ^ index, 32'hC39A7654 ^ (index * 7919)};
    endfunction
    function automatic [63:0] hidden_word(input integer b, input integer word_addr);
        integer k;
        begin
            for (k = 0; k < 8; k = k + 1)
                hidden_word[8*k +: 8] = expected_hidden[b*128 + word_addr*8 + k];
        end
    endfunction

    task check_fifo;
        begin
            check(fifo_empty === (expected_fifo.size() == 0), "FIFO empty disagrees with queue");
            check(fifo_full === (expected_fifo.size() == 512), "FIFO full disagrees with queue");
            if (expected_fifo.size() != 0)
                check(fifo_rdata === expected_fifo[0],
                      $sformatf("FWFT head expected=%016h actual=%016h count=%0d",
                                expected_fifo[0], fifo_rdata, expected_fifo.size()));
        end
    endtask

    // Acceptance uses the pre-edge queue size. Full rejects write even with
    // pop. A full-write is misuse that Top must prevent, not a FIFO defect.
    task fifo_step(input bit we, input bit re, input [63:0] data);
        integer before_size;
        reg [63:0] popped_word;
        reg [8:0] old_read_ptr, old_write_ptr;
        begin
            @(negedge clk);
            fifo_we = we; fifo_re = re; fifo_wdata = data;
            #1; check_fifo();
            before_size = expected_fifo.size();
            old_read_ptr = u_fifo.read_ptr_reg;
            old_write_ptr = u_fifo.write_ptr_reg;
            @(posedge clk);
            if (re && before_size != 0) begin
                if (fifo_rdata === DROP_FULL_POP || fifo_rdata === DROP_FULL_ONLY)
                    dropped_marker_seen = dropped_marker_seen + 1;
                check(fifo_rdata === expected_fifo[0], "FIFO pop data/order mismatch");
                popped_word = expected_fifo.pop_front();
                pops = pops + 1;
            end else if (re) empty_pop = empty_pop + 1;
            if (we && before_size < 512) begin
                expected_fifo.push_back(data);
                pushes = pushes + 1;
            end else if (we) full_drop = full_drop + 1;
            if (we && re && before_size > 0 && before_size < 512)
                simultaneous = simultaneous + 1;
            #1;
            check_fifo();
            check(u_fifo.count_reg === expected_fifo.size(), "FIFO occupancy disagrees with independent queue");
            if (re && before_size == 0)
                check(u_fifo.read_ptr_reg === old_read_ptr, "empty pop moved read pointer");
            if (we && before_size == 512)
                check(u_fifo.write_ptr_reg === old_write_ptr, "rejected full write moved write pointer");
        end
    endtask

    task test_fifo;
        reg [8:0] old_read_ptr, old_write_ptr;
        reg [9:0] old_count;
        reg [63:0] preserved_ram;
        begin
            fifo_start_cycle = cycles;
            check_fifo();
            for (i = 0; i < 512; i = i + 1) begin
                fifo_step(1,0,pattern(i));
                if (i == 510) check(!fifo_full && u_fifo.count_reg == 511, "511 must not be full");
            end
            check(fifo_full && u_fifo.count_reg == 512, "512 must be full");
            // Stall without popping: the first word is already visible.
            repeat (8) fifo_step(0,0,64'd0);
            for (i = 0; i < 512; i = i + 1) fifo_step(0,1,64'd0);
            check(fifo_empty && u_fifo.count_reg == 0, "512 pops must empty FIFO");
            $display("PASS: Y1 FIFO pushes=512 pops=512 full_at=512 not_full_at=511 FWFT_without_pop=1 held_head_cycles=8 empty_after_drain=1");

            old_read_ptr = u_fifo.read_ptr_reg; old_write_ptr = u_fifo.write_ptr_reg;
            repeat (4) fifo_step(0,1,64'd0);
            check(u_fifo.read_ptr_reg === old_read_ptr && u_fifo.write_ptr_reg === old_write_ptr,
                  "empty read changed a pointer");
            $display("PASS: Y2 empty_pop_attempts=4 pointer_changes=0 empty=1");

            for (i = 0; i < 512; i = i + 1) fifo_step(1,0,pattern(1000+i));
            fifo_step(0,1,64'd0);
            check(!fifo_full && u_fifo.count_reg == 511, "full pop must give 511");
            fifo_step(1,0,pattern(1512));
            check(fifo_full && u_fifo.count_reg == 512, "write after pop must restore 512");
            $display("PASS: Y2 full_pop occupancy=511 full=0 next_write_accepted=1 occupancy_after_write=512");
            saved_pops = pops;
            fifo_step(1,1,DROP_FULL_POP);
            check(u_fifo.count_reg == 511 && !fifo_full, "full simultaneous write/read must give 511");
            for (i = 0; i < 511; i = i + 1) fifo_step(0,1,64'd0);
            check(fifo_empty && pops-saved_pops == 512 && dropped_marker_seen == 0,
                  "full+pop dropped marker resurfaced or valid words lost");
            $display("PASS: Y2/Y3 full_simultaneous occupancy=512->511 rejected=%016h later_pops=511 dropped_word_seen=0 all_512_valid_words_preserved=1", DROP_FULL_POP);

            for (i = 0; i < 512; i = i + 1) fifo_step(1,0,pattern(2000+i));
            saved_pops = pops;
            fifo_step(1,0,DROP_FULL_ONLY);
            check(fifo_full && u_fifo.count_reg == 512, "full write without pop changed occupancy");
            for (i = 0; i < 512; i = i + 1) fifo_step(0,1,64'd0);
            check(pops-saved_pops == 512 && dropped_marker_seen == 0, "full-only marker resurfaced");
            $display("PASS: Y3 full_write occupancy=512->512 rejected=%016h later_pops=512 dropped_word_seen=0 Top_must_block_full_write=1", DROP_FULL_ONLY);

            // Empty read cannot consume the word being written at that edge.
            fifo_step(1,1,pattern(3000));
            check(u_fifo.count_reg == 1, "empty simultaneous write/read must keep newly written word");
            // Repeated count-one replacement exercises the RAM collision bypass.
            repeat (64) begin
                fifo_step(1,1,pattern(3001+simultaneous));
                check(u_fifo.count_reg == 1, "single-word simultaneous replacement lost occupancy");
            end
            fifo_step(0,1,64'd0);
            $display("PASS: Y2 empty_simultaneous occupancy=0->1 single_word_replacements=64 FWFT_no_bubble=1");

            for (i = 0; i < 511; i = i + 1) fifo_step(1,0,pattern(4000+i));
            saved_pushes = pushes; saved_pops = pops;
            for (i = 0; i < 2048; i = i + 1) begin
                fifo_step(1,1,pattern(5000+i));
                check(u_fifo.count_reg == 511 && !fifo_full, "full-minus-one simultaneous occupancy changed");
            end
            check(pushes-saved_pushes == 2048 && pops-saved_pops == 2048, "wrap transfer count");
            for (i = 0; i < 511; i = i + 1) fifo_step(0,1,64'd0);
            $display("PASS: Y2 simultaneous_below_full=2048 occupancy=511 pointer_wraps_each=4 ordered_words_compared=2559 mismatches=0");

            // Reproducible legal producer/consumer stalls across empty/full.
            for (i = 0; i < 4096; i = i + 1) begin
                rng = rng ^ (rng << 13); rng = rng ^ (rng >> 17); rng = rng ^ (rng << 5);
                fifo_step(rng[0] && expected_fifo.size()<512,rng[1],pattern(10000+i));
            end
            while (expected_fifo.size()!=0) fifo_step(0,1,64'd0);
            $display("PASS: Y2 random_stalls seed=F0015128 cycles=4096 final_empty=1 dropped_marker_seen=%0d",dropped_marker_seen);

            // Reset only pointers/count/control, not stored words. Exercise a
            // partially occupied FIFO and suppress an attempted reset write.
            repeat (3) fifo_step(1,0,pattern(20000+pushes));
            @(negedge clk);
            old_read_ptr = u_fifo.read_ptr_reg; old_write_ptr = u_fifo.write_ptr_reg;
            old_count = u_fifo.count_reg; preserved_ram = u_fifo.mem[old_write_ptr];
            rst_n = 0; fifo_we = 1; fifo_re = 1; fifo_wdata = 64'hBAD0_BAD0_BAD0_BAD0;
            #1;
            check(u_fifo.count_reg === old_count && u_fifo.read_ptr_reg === old_read_ptr &&
                  u_fifo.write_ptr_reg === old_write_ptr, "FIFO reset acted without clock edge");
            @(posedge clk); #1;
            expected_fifo.delete();
            check_fifo();
            check(u_fifo.read_ptr_reg == 0 && u_fifo.write_ptr_reg == 0 && u_fifo.count_reg == 0,
                  "FIFO reset did not clear pointers/count");
            check(u_fifo.mem[old_write_ptr] === preserved_ram, "FIFO reset wrote/cleared memory");
            @(negedge clk); rst_n = 1; fifo_we = 0; fifo_re = 0;
            fifo_step(1,0,pattern(30000)); fifo_step(0,1,64'd0);
            check(full_drop == 2 && dropped_marker_seen == 0, "expected exactly two rejected full writes");
            $display("PASS: Y1/Y2 synchronous_reset occupancy=3->0 pointers=0 storage_retained=1 fresh_push_pop=1");
            $display("PASS: Y1-Y3 FIFO pushes=%0d pops=%0d reset_discarded=3 full_write_dropped=%0d dropped_markers_seen=%0d simultaneous_accepted=%0d empty_pop_ignored=%0d cycles=%0d",
                     pushes,pops,full_drop,dropped_marker_seen,simultaneous,empty_pop,cycles-fifo_start_cycle);
        end
    endtask

    task hidden_write(input integer b, input integer a, input [7:0] data);
        begin
            @(negedge clk);
            hidden_we = 1; hidden_wbank = b; hidden_waddr = a; hidden_wdata = data;
            @(posedge clk); #1;
            expected_hidden[b*128+a] = data;
            @(negedge clk); hidden_we = 0;
        end
    endtask
    task hidden_read(input integer b, input integer a);
        reg [63:0] held;
        begin
            @(negedge clk); held = hidden_rdata;
            hidden_rbank = b; hidden_raddr = a;
            #1; check(hidden_rdata === held, "hidden changed before read sampling edge");
            @(posedge clk); #1;
            check(hidden_rdata === hidden_word(b,a),
                  $sformatf("hidden bank=%0d word=%0d expected=%016h actual=%016h",
                            b,a,hidden_word(b,a),hidden_rdata));
        end
    endtask
    task pose_write(input integer a, input [7:0] data);
        reg [191:0] held;
        begin
            @(negedge clk); held = pose_data;
            pose_we = 1; pose_waddr = a; pose_wdata = data;
            #1; check(pose_data === held, "pose changed before write sampling edge");
            @(posedge clk); #1;
            expected_pose[8*a +: 8] = data;
            check(pose_data === expected_pose, $sformatf("pose byte=%0d write/hold mismatch",a));
            @(negedge clk); pose_we = 0;
        end
    endtask

    task test_hidden_pose;
        begin
            for (bank = 0; bank < 2; bank = bank + 1)
                for (i = 0; i < 128; i = i + 1)
                    hidden_write(bank,i,(i*29 + 3) ^ (bank ? 8'hB7 : 8'h00));
            for (i = 0; i < 16; i = i + 1) begin
                hidden_read(0,i);
                hidden_read(1,15-i);
            end
            $display("PASS: Y4 two banks bytes=256 words=32 lane_order=low_address_low_byte read_latency=1 cycle");
            // Exercise collisions in every byte lane, not just lane zero.
            for (j = 0; j < 8; j = j + 1) begin
                @(negedge clk);
                hidden_rbank = 1; hidden_raddr = 7;
                hidden_we = 1; hidden_wbank = 1; hidden_waddr = 56+j;
                hidden_wdata = expected_hidden[184+j] ^ 8'hFF;
                expected_read = hidden_word(1,7);
                @(posedge clk); #1;
                check(hidden_rdata === expected_read, "hidden same-address collision must return OLD byte");
                expected_hidden[184+j] = hidden_wdata;
                @(negedge clk); hidden_we = 0;
                @(posedge clk); #1;
                check(hidden_rdata === hidden_word(1,7), "hidden new byte not visible on following read");
            end
            $display("PASS: Y4 same-word read/write collisions=8 read-first=8 next_read_new_data=8");
            // Guard unused high bits rather than accidentally aliasing a bank.
            @(negedge clk);
            hidden_we = 1; hidden_wbank = 1; hidden_waddr = 8'h80;
            hidden_wdata = 8'hDE; hidden_raddr = 5'd16;
            @(posedge clk); #1;
            check(hidden_rdata === 64'd0, "hidden invalid read must return zero");
            @(negedge clk); hidden_we = 0;
            hidden_read(1,0);
            $display("PASS: Y4 unused address bits invalid_write_ignored=1 invalid_read_zero=1 valid_bytes_unchanged=8");

            // Memory is intentionally uninitialized; compare known bytes only
            // until all 24 entries have been explicitly written once.
            expected_pose = {192{1'bx}};
            for (i = 0; i < 24; i = i + 1) pose_write(i,8'h21+i*7);
            $display("PASS: Y5 pose bytes=24 parallel_bits=192 byte_k_at_8k=24");
            pose_write(0,8'hE1); pose_write(11,8'h57); pose_write(23,8'h9A);
            @(negedge clk); old_pose = pose_data;
            pose_we = 1; pose_waddr = 5'd24; pose_wdata = 8'hFF;
            @(posedge clk); #1;
            check(pose_data === old_pose, "pose out-of-range write corrupted storage");
            @(negedge clk); pose_we = 0;
            repeat (7) begin
                @(posedge clk); #1;
                check(pose_data === expected_pose, "pose changed without write");
            end
            $display("PASS: Y5 partial_writes=3 other_bytes_held=21 idle_hold_cycles=7 invalid_write_ignored=1");

            // Assert reset between edges: no asynchronous data-output clear.
            @(negedge clk); old_hidden = hidden_rdata;
            rst_n = 0; hidden_we = 1; hidden_wbank = 0; hidden_waddr = 0;
            hidden_wdata = 8'hEF; pose_we = 1; pose_waddr = 0; pose_wdata = 8'hEF;
            #1; check(hidden_rdata === old_hidden, "hidden reset is asynchronous");
            repeat (2) begin
                @(posedge clk); #1;
                check(hidden_rdata === 64'd0, "hidden output register reset");
                check(pose_data === expected_pose, "pose storage must survive reset");
            end
            @(negedge clk); hidden_we = 0; pose_we = 0; rst_n = 1;
            for (i = 0; i < 16; i = i + 1) begin hidden_read(0,i); hidden_read(1,i); end
            check(pose_data === expected_pose, "pose storage after reset release");
            $display("PASS: Y4/Y5 reset hidden_retained_bytes=256 pose_retained_bytes=24 writes_during_reset_ignored=1");
            $display("OBS: Y5 parallel pose output shows OLD value before write edge and NEW value after edge; no clocked read port");
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk); rst_n = 1;

        test_hidden_pose();
        // Run the unchanged Y4/Y5 first, retaining their exact baseline window.
        saved_checks = checks; saved_cycles = cycles;
        if (saved_checks != 215 || saved_cycles != 663)
            $fatal(1,"FAIL: Y4/Y5 baseline changed checks=%0d cycles=%0d",saved_checks,saved_cycles);
        $display("PASS: Y4/Y5 baseline unchanged checks=%0d cycles=%0d",saved_checks,saved_cycles);
        test_fifo();
        $display("PASS: tb_fc_storage ALL Y1-Y5 cases complete checks=%0d cycles=%0d",checks,cycles);
        $finish;
    end
endmodule
