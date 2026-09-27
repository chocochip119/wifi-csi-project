`timescale 1ns / 1ps

// TB-only FC stages and standard 512-word FC1 FIFO. No CNN arithmetic.
module fc_stub (
    input wire clk, resetn, fc_start,
    input wire [1:0] fc_sel,
    input wire fifo_we,
    input wire [63:0] fifo_wdata,
    output wire fifo_full,
    output reg fc_done,
    output reg [191:0] pose_data,
    output reg [8:0] fc_param_raddr,
    input wire [95:0] fc_param_rdata,
    output reg [9:0] fc_lut_raddr,
    input wire [7:0] fc_lut_rdata,
    output reg [11:0] fcw_raddr,
    input wire [63:0] fcw_rdata,
    output reg [8:0] flat_raddr,
    input wire [63:0] flat_rdata
);
    initial begin fc_param_raddr=0;fc_lut_raddr=0;fcw_raddr=0;flat_raddr=0;end
    // X-02a opt-in RAM consumer. Default off preserves all legacy timing/data.
    // Testbench supplies file-derived RAM goldens and observed Pool write data.
    // This digest is a wiring stimulus, NOT FC arithmetic or a valid pose model.
    bit ram_test_enable=0, ram_golden_ready=0;
    // Checker-only ownership indication from the TB. It never aborts the FC,
    // stops its addresses/FIFO, or changes done. D08 may revoke shared ports
    // in ERR_DRAIN while this operation remains active until common reset.
    bit ram_shared_owned=1;
    integer unowned_param_reads=0,unowned_lut_reads=0;
    reg [95:0] golden_param[0:327];
    reg [7:0] golden_lut[0:1023];
    reg [63:0] golden_fcw[0:2431], golden_flat[0:383];
    reg [191:0] feature_digest=0;
    integer ram_last_start=0,ram_step=0;
    integer param_reads[0:2],lut_reads[0:2],fcw_reads[0:2],flat_reads=0;
    bit request_param=0,request_lut=0,request_fcw=0,request_flat=0;
    integer request_stage=0;
    integer consume_mode=0; // 0 every cycle, 1 fixed period, 2 random, 3 pause/resume
    integer consume_period=4, pause_after=1024, pause_cycles=2000;
    integer expected_words=49152, done_delay_cycles=5, done_width_cycles=1;
    // FC2/3 respond no earlier than the edge following START. Zero means
    // no extra wait beyond that one synchronous cycle, keeping START pulses distinct.
    integer fc2_delay_cycles=3, fc3_delay_cycles=4;
    integer fc2_done_width_cycles=1, fc3_done_width_cycles=1;
    reg [191:0] pose_value=192'h17161514131211100f0e0d0c0b0a09080706050403020100;
    integer phase_starts[0:2], phase_dones[0:2], phase_start_cycle[0:2], phase_done_cycle[0:2];
    // Explicit negative-test budget only. Unexpected non-idle START stays fatal;
    // an expected rejected START leaves the old operation intact, never aborts it.
    integer expected_busy_starts=0, rejected_starts=0, pulse_width_reg=1;
    // 0: real completion after all pops. 1/2 are explicit control-test injections:
    // 1: done on the last push; 2: done after early_done_after pops.
    integer done_mode=0, early_done_after=1024;
    reg [31:0] seed=32'h1234abcd, random_state;
    reg [63:0] fifo [0:511];
    reg [63:0] pushed [0:49151], consumed [0:49151];
    reg [1:0] selected_reg;
    integer count=0, write_ptr=0, read_ptr=0, push_count=0, pop_count=0;
    integer accepted_starts=0, done_count=0, violations=0;
    integer cycle_count=0, start_cycle=0, done_cycle=0, last_pop_cycle=0;
    integer full_cycles=0, full_run=0, max_full_run=0, max_count=0;
    integer simultaneous=0, sel_changed_cycles=0, cooldown=0, pause_left=0;
    integer completion_left=0, width_left=0;
    bit active=0, completing=0, paused_once=0, injected_done=0, prior_start=0;
    bit pop_now, emit_done;

    assign fifo_full=(count==512);
    function automatic [31:0] next_random(input reg [31:0] value);
        reg [31:0] x;
        begin
            x=value==0 ? 32'd1:value;
            x=x^(x<<13); x=x^(x>>17); next_random=x^(x<<5);
        end
    endfunction
    task automatic fail(input string message);
        begin violations=violations+1; $fatal(1,"FAIL: fc_stub %s",message); end
    endtask

    always @(posedge clk) begin
        if (!resetn) begin
            fc_done<=0; active<=0; completing<=0; prior_start<=0;
            pose_data<=0; rejected_starts<=0; expected_busy_starts<=0; pulse_width_reg<=1;
            for(integer j=0;j<3;j=j+1) begin
                phase_starts[j]<=0;phase_dones[j]<=0;phase_start_cycle[j]<=0;phase_done_cycle[j]<=0;
            end
            count<=0; write_ptr<=0; read_ptr<=0; push_count<=0; pop_count<=0;
            accepted_starts<=0; done_count<=0; selected_reg<=0;
            cycle_count<=0; start_cycle<=0; done_cycle<=0; last_pop_cycle<=0;
            full_cycles<=0; full_run<=0; max_full_run<=0; max_count<=0;
            simultaneous<=0; sel_changed_cycles<=0; cooldown<=0; pause_left<=0;
            completion_left<=0; width_left<=0; paused_once<=0; injected_done<=0;
            random_state<=seed;
        end else begin
            cycle_count<=cycle_count+1;
            emit_done=0; pop_now=0;
            if (fc_start && prior_start) fail("START exceeds one cycle");
            prior_start<=fc_start;
            if (fc_done && pulse_width_reg!=0) begin
                if (width_left<=1) fc_done<=0;
                else width_left<=width_left-1;
            end
            if (active && fc_sel!==selected_reg) sel_changed_cycles<=sel_changed_cycles+1;
            if (fifo_full) begin
                full_cycles<=full_cycles+1; full_run<=full_run+1;
                if (full_run+1>max_full_run) max_full_run<=full_run+1;
            end else full_run<=0;
            if (count>max_count) max_count<=count;
            if (fifo_we !== 1'b0 && fifo_we !== 1'b1) fail("unknown FIFO write enable");
            if (fifo_we && fifo_full) fail("push while full");
            if (fc_start) begin
                if (active || count!=0) begin
                    if(expected_busy_starts==0) fail("START while non-idle");
                    else begin
                        expected_busy_starts<=expected_busy_starts-1;
                        rejected_starts<=rejected_starts+1;
                        $display("OBS: expected FC non-idle START rejected; selected=%0d active=%b count=%0d pushes=%0d pops=%0d",
                            selected_reg,active,count,push_count,pop_count);
                    end
                end else begin
                    if ((^fc_sel)===1'bx || fc_sel>2) fail("invalid FC selector");
                    if (expected_words<1 || expected_words>49152 || consume_period<1 ||
                        done_delay_cycles<0 || done_width_cycles<0 || pause_cycles<0 ||
                        fc2_delay_cycles<0 || fc3_delay_cycles<0 || fc2_done_width_cycles<0 || fc3_done_width_cycles<0)
                        fail("invalid configuration");
                    if(fc_sel!=0 && (selected_reg!=fc_sel-1 || pop_count!=expected_words))
                        fail("FC2/3 START before predecessor completed");
                    active<=1; completing<=0; selected_reg<=fc_sel; fc_done<=0;
                    accepted_starts<=accepted_starts+1; start_cycle<=cycle_count;
                    phase_starts[fc_sel]<=phase_starts[fc_sel]+1;phase_start_cycle[fc_sel]<=cycle_count;
                    if(fc_sel==0) begin
                        pulse_width_reg<=done_width_cycles;
                        push_count<=0; pop_count<=0; write_ptr<=0; read_ptr<=0; count<=0;
                        cooldown<=0; pause_left<=0; paused_once<=0; injected_done<=0;
                        random_state<=seed;
                        full_cycles<=0; full_run<=0; max_full_run<=0; max_count<=0;
                        simultaneous<=0; sel_changed_cycles<=0;
                    end else begin
                        completing<=1;
                        completion_left<=fc_sel==1 ? (fc2_delay_cycles==0?1:fc2_delay_cycles) :
                            (fc3_delay_cycles==0?1:fc3_delay_cycles);
                        pulse_width_reg<=fc_sel==1?fc2_done_width_cycles:fc3_done_width_cycles;
                    end
                end
            end else if (active && !completing && selected_reg==0) begin
                if (cooldown>0) cooldown<=cooldown-1;
                if (pause_left>0) pause_left<=pause_left-1;
                if (consume_mode==3 && !paused_once && push_count>=pause_after) begin
                    paused_once<=1; pause_left<=pause_cycles;
                end else if (count>0) begin
                    case(consume_mode)
                        0: pop_now=1;
                        1: pop_now=(cooldown==0);
                        2: begin
                            random_state<=next_random(random_state);
                            pop_now=(next_random(random_state)%4==0);
                        end
                        3: pop_now=(pause_left==0);
                        default: fail("invalid consumer mode");
                    endcase
                end
                // No empty bypass: a push cannot be popped until a later edge.
                if (pop_now) begin
                    if (pop_count>=expected_words) fail("more pops than expected");
                    consumed[pop_count]<=fifo[read_ptr];
                    pop_count<=pop_count+1; read_ptr<=(read_ptr==511)?0:read_ptr+1;
                    last_pop_cycle<=cycle_count;
                    if (consume_mode==1) cooldown<=consume_period-1;
                    if (pop_count+1==expected_words) begin
                        if (done_mode==0) begin
                            if (done_delay_cycles==0) begin emit_done=1; active<=0; end
                            else begin completing<=1; completion_left<=done_delay_cycles; end
                        end else active<=0;
                    end
                    if (done_mode==2 && !injected_done && pop_count+1==early_done_after) begin
                        emit_done=1; injected_done<=1;
                    end
                end
                case ({fifo_we,pop_now})
                    2'b10: count<=count+1;
                    2'b01: count<=count-1;
                    2'b11: simultaneous<=simultaneous+1;
                    default: begin end
                endcase
            end
            if (fifo_we) begin
                if (!active || completing || selected_reg!=0) fail("push while FC inactive/completing/non-FC1");
                if ((^fifo_wdata)===1'bx) fail("unknown FIFO data");
                if (push_count>=expected_words) fail("more pushes than expected");
                fifo[write_ptr]<=fifo_wdata; pushed[push_count]<=fifo_wdata;
                write_ptr<=(write_ptr==511)?0:write_ptr+1; push_count<=push_count+1;
                if (done_mode==1 && !injected_done && push_count+1==expected_words) begin
                    emit_done=1; injected_done<=1;
                end
            end
            if (completing) begin
                if (completion_left==1) begin
                    emit_done=1; active<=0; completing<=0;
                end else completion_left<=completion_left-1;
            end
            if (emit_done) begin
                fc_done<=1; width_left<=pulse_width_reg;
                done_count<=done_count+1; done_cycle<=cycle_count;
                phase_dones[selected_reg]<=phase_dones[selected_reg]+1;phase_done_cycle[selected_reg]<=cycle_count;
                if(selected_reg==2) pose_data<=ram_test_enable ? feature_digest : pose_value;
            end
            if (count<0 || count>512) fail("FIFO count outside 0..512");
        end
    end

    // Change addresses only during our operation; retain final values in idle.
    // Drivers run on falling edges, check synchronous RAM results after rising edges.
    always @(negedge clk) begin
        request_param=0;request_lut=0;request_fcw=0;request_flat=0;
        if(!resetn) begin
            fc_param_raddr=0;fc_lut_raddr=0;fcw_raddr=0;flat_raddr=0;
            ram_last_start=0;ram_step=0;flat_reads=0;feature_digest=0;
            unowned_param_reads=0;unowned_lut_reads=0;
            for(integer k=0;k<3;k=k+1) begin param_reads[k]=0;lut_reads[k]=0;fcw_reads[k]=0;end
        end else if(ram_test_enable && active) begin
            if(!ram_golden_ready) fail("RAM test enabled without independent goldens");
            if(ram_last_start!=accepted_starts) begin
                ram_last_start=accepted_starts;ram_step=0;
                param_reads[selected_reg]=0;lut_reads[selected_reg]=0;fcw_reads[selected_reg]=0;
                if(selected_reg==0) begin flat_reads=0;feature_digest=192'h13579bdf2468ace00123456789abcdef6a09e667bb67ae85;end
            end
            request_stage=int'(selected_reg);
            if(ram_step<(selected_reg==2?24:128)) begin
                fc_param_raddr=9'((selected_reg==0?48:selected_reg==1?176:304)+ram_step);
                request_param=1;
            end
            if(selected_reg<2 && ram_step<256) begin
                fc_lut_raddr=10'((selected_reg==0?512:768)+ram_step);request_lut=1;
            end
            if(selected_reg>0 && ram_step<(selected_reg==1?2048:384)) begin
                fcw_raddr=12'((selected_reg==1?0:2048)+ram_step);request_fcw=1;
            end
            if(selected_reg==0 && ram_step<384) begin flat_raddr=9'(ram_step);request_flat=1;end
            ram_step=ram_step+1;
        end
    end
    always @(posedge clk) begin : ram_observer
        bit owns_shared_at_edge;
        owns_shared_at_edge=ram_shared_owned;
        if(resetn && ram_test_enable) begin
            #1;
            if(request_param && owns_shared_at_edge) begin
                if(fc_param_rdata!==golden_param[fc_param_raddr])
                    fail($sformatf("param stage=%0d addr=%0d expected=%h actual=%h",request_stage,fc_param_raddr,golden_param[fc_param_raddr],fc_param_rdata));
                param_reads[request_stage]=param_reads[request_stage]+1;
            end else if(request_param) unowned_param_reads=unowned_param_reads+1;
            if(request_lut && owns_shared_at_edge) begin
                if(fc_lut_rdata!==golden_lut[fc_lut_raddr]) fail($sformatf("LUT stage=%0d addr=%0d",request_stage,fc_lut_raddr));
                lut_reads[request_stage]=lut_reads[request_stage]+1;
            end else if(request_lut) unowned_lut_reads=unowned_lut_reads+1;
            if(request_fcw) begin
                if(fcw_rdata!==golden_fcw[fcw_raddr]) fail($sformatf("FCW stage=%0d addr=%0d",request_stage,fcw_raddr));
                fcw_reads[request_stage]=fcw_reads[request_stage]+1;
            end
            if(request_flat) begin
                if($isunknown(flat_rdata) || flat_rdata!==golden_flat[flat_raddr])
                    fail($sformatf("flat addr=%0d expected=%h actual=%h",flat_raddr,golden_flat[flat_raddr],flat_rdata));
                flat_reads=flat_reads+1;
                feature_digest[63:0]={feature_digest[56:0],feature_digest[63:57]} ^ flat_rdata;
                feature_digest[127:64]=feature_digest[127:64]+flat_rdata+64'(flat_raddr);
                feature_digest[191:128]={feature_digest[180:128],feature_digest[191:181]} ^
                    (flat_rdata+64'h9e3779b97f4a7c15);
            end
        end
    end
endmodule
