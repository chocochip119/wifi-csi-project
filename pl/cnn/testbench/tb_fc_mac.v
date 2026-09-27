`timescale 1ns / 1ps

module tb_fc_mac;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, mac_start = 0;
    reg [1:0] mac_sel = 0;
    wire mac_done, acc_valid;
    wire signed [31:0] acc;
    wire [8:0] acc_tag, flat_raddr;
    wire [4:0] hidden_raddr;
    wire [11:0] fcw_raddr;
    reg [63:0] flat_rdata = 0;
    wire [63:0] hidden_rdata, fcw_rdata, fifo_rdata;
    wire fifo_re, fifo_empty, fifo_full;
    reg fifo_we = 0;
    reg [63:0] fifo_wdata = 0;
    reg hidden_we = 0, hidden_wbank = 0;
    reg [7:0] hidden_waddr = 0, hidden_wdata = 0;
    reg fcw_we = 0;
    reg [11:0] fcw_waddr = 0;
    reg [63:0] fcw_wdata = 0;
    reg empty_probe = 0;
    wire fifo_read_input = fifo_re || (empty_probe && fifo_empty);

    fc_mac dut (.*);
    fc1_weight_fifo weights_fifo (
        .clk(clk),.rst_n(rst_n),.fifo_we(fifo_we),.fifo_wdata(fifo_wdata),
        .fifo_full(fifo_full),.fifo_re(fifo_read_input),.fifo_rdata(fifo_rdata),.fifo_empty(fifo_empty)
    );
    // MAC r51 packs bank in bit4. F-01 storage has separate bank and local
    // address ports, so unpack without changing the F-01 module or interface.
    hidden_buffer hidden (
        .clk(clk),.rst_n(rst_n),.hidden_we(hidden_we),.hidden_wbank(hidden_wbank),
        .hidden_waddr(hidden_waddr),.hidden_wdata(hidden_wdata),
        .hidden_rbank(hidden_raddr[4]),.hidden_raddr({1'b0,hidden_raddr[3:0]}),.hidden_rdata(hidden_rdata)
    );
    fcw_ram resident_weights (.*);

    reg [7:0] blob [0:422991];
    reg [63:0] flat_golden [0:383], flat_mem [0:383];
    reg [7:0] hidden0_golden [0:127], hidden1_golden [0:127];
    reg signed [31:0] gold1 [0:127], gold2 [0:127], gold3 [0:23];
    reg [7:0] activation [0:3071];
    integer cycles = 0, checks = 0, cases = 0, outputs_checked = 0, mismatches = 0;
    integer layer = 0, variant = 0, in_count, out_count, words_per_output, total_words;
    integer produced = 0, issued = 0, received = 0, full_cycles = 0, stall_cycles = 0;
    integer empty_attempts = 0, busy_starts = 0, stretched_intervals = 0;
    integer start_cycle, last_acc_cycle, first_acc_cycle, previous_acc_cycle;
    integer issue_end [0:127];
    integer changed_outputs, act_index, weight_index, change_delta;
    integer fd, count, i, j, k, n, found, nonzero_count, elapsed;
    integer negative_count, min_sum, max_sum;
    reg [31:0] guard, rng = 32'hFC020123;
    reg producer_on = 0, collect = 0, stall_mode = 0;
    reg previous_valid = 0, previous_done = 0;
    reg [8:0] old_fifo_pointer;
    reg probe_was_empty;
    reg signed [63:0] observed_with_bias, expected_with_bias, pure_sum, bound_margin;
    string case_name;

    always @(posedge clk) flat_rdata <= flat_mem[flat_raddr];
    initial begin #20000000; $fatal(1,"FAIL: F-02 global timeout"); end
    task check(input bit ok, input string message);
        begin
            checks = checks + 1;
            if (!ok) $fatal(1,"FAIL: case=%s cycle=%0d %s",case_name,cycles,message);
        end
    endtask
    function automatic integer s8(input [7:0] x);
        s8 = (x >= 128) ? (integer'(x)-256) : integer'(x);
    endfunction
    function automatic integer inputs(input integer which);
        inputs = (which==0) ? 3072 : 128;
    endfunction
    function automatic integer outputs(input integer which);
        outputs = (which==2) ? 24 : 128;
    endfunction
    function automatic integer weight_offset(input integer which);
        case(which) 0:weight_offset=5936; 1:weight_offset=400688; default:weight_offset=418608; endcase
    endfunction
    function automatic integer bias(input integer which, input integer o);
        integer b;
        begin
            case(which) 0:b=99788*4; 1:b=104268*4; default:b=105420*4; endcase
            b=b+4*o;
            bias=$signed({blob[b+3],blob[b+2],blob[b+1],blob[b]});
        end
    endfunction
    function automatic integer golden(input integer which, input integer o);
        case(which) 0:golden=gold1[o]; 1:golden=gold2[o]; default:golden=gold3[o]; endcase
    endfunction
    function automatic [7:0] activation_byte(input integer which, input integer index);
        case(which)
            0:activation_byte=flat_golden[index/8][8*(index%8) +: 8];
            1:activation_byte=hidden0_golden[index];
            default:activation_byte=hidden1_golden[index];
        endcase
    endfunction
    function automatic [7:0] weight_byte(input integer which, input integer index);
        reg [7:0] value;
        begin
            value=blob[weight_offset(which)+index];
            if (which==layer) begin
                if (variant==2 && index==weight_index) value=s8(value)+change_delta;
                if (variant==3) value=8'h80;
                if (variant==4) value=8'h7F;
            end
            weight_byte=value;
        end
    endfunction
    function automatic [63:0] weight_word(input integer which, input integer index);
        integer b;
        begin
            for(b=0;b<8;b=b+1) weight_word[8*b +: 8]=weight_byte(which,index*8+b);
        end
    endfunction
    function automatic signed [63:0] expected_acc_bias(input integer o);
        reg signed [63:0] result;
        begin
            result=golden(layer,o);
            if(variant==1)
                result=result+change_delta*s8(blob[weight_offset(layer)+o*in_count+act_index]);
            if(variant==2 && o==weight_index/in_count)
                result=result+change_delta*s8(activation_byte(layer,weight_index%in_count));
            if(variant==3) result=64'sd16384*in_count+bias(layer,o);
            if(variant==4) result=-64'sd16256*in_count+bias(layer,o);
            expected_acc_bias=result;
        end
    endfunction

    // Producer obeys full, including full+pop. Long pauses and seeded gaps
    // create genuine empty stalls in the real F-01 FIFO.
    always @(negedge clk) begin
        fifo_we=0;
        if (rst_n && producer_on && produced<49152) begin
            rng=rng^(rng<<13); rng=rng^(rng>>17); rng=rng^(rng<<5);
            elapsed=cycles-start_cycle;
            if (!fifo_full && (!stall_mode || !collect ||
                (!(elapsed>=700 && elapsed<1700) && rng[2:0]!=3'd0))) begin
                fifo_we=1;
                fifo_wdata=weight_word(0,produced);
            end
        end
    end

    // Observe request addresses before the edge and result outputs after NBA.
    // No DUT counters/state are used to decide how many groups are expected.
    always @(posedge clk) begin
        cycles=cycles+1;
        probe_was_empty=0;
        if(rst_n && producer_on) begin
            if(fifo_we) begin
                check(!fifo_full,"producer overflow");
                produced=produced+1;
            end
            if(fifo_full && produced<49152) full_cycles=full_cycles+1;
        end
        if(rst_n && collect) begin
            if(mac_start) busy_starts=busy_starts+1;
            if(layer==0) begin
                if(fifo_empty && issued<total_words) stall_cycles=stall_cycles+1;
                if(empty_probe && fifo_empty) begin
                    old_fifo_pointer=weights_fifo.read_ptr_reg;
                    probe_was_empty=1;
                    empty_attempts=empty_attempts+1;
                end
                if(fifo_re) begin
                    check(!fifo_empty,"MAC popped empty FIFO");
                    check(issued<total_words,"too many FIFO pops");
                    check(flat_raddr===issued%384,"FC1 flat address sequence");
                    check(fifo_rdata===weight_word(0,issued),"FC1 FIFO full stream/order compare");
                    if(issued%words_per_output==words_per_output-1)
                        issue_end[issued/words_per_output]=cycles;
                    issued=issued+1;
                end
            end else begin
                check(!fifo_re,"FC2/3 must not pop FIFO");
                if(issued<total_words) begin
                    check(hidden_raddr===((layer==2 ? 16:0)+(issued%16)),"hidden bank/word address");
                    check(fcw_raddr===((layer==2 ? 2048:0)+issued),"FCW contiguous address coverage");
                    if(issued%16==15) issue_end[issued/16]=cycles;
                    issued=issued+1;
                end
            end
        end
        #1;
        if(rst_n && collect) begin
            if(probe_was_empty) check(weights_fifo.read_ptr_reg===old_fifo_pointer,"empty FIFO read changed pointer");
            check(!(acc_valid && previous_valid),"acc_valid pulse wider than one cycle");
            check(!(mac_done && previous_done),"mac_done pulse wider than one cycle");
            if(acc_valid) begin
                check(received<out_count,"too many accumulator outputs");
                check(acc_tag===(layer*128+received),$sformatf("tag expected=%03h actual=%03h",layer*128+received,acc_tag));
                check(cycles==issue_end[received]+6,"RAM/product/tree alignment: result must follow final issue by 6 cycles");
                if(received==0) first_acc_cycle=cycles;
                else begin
                    if(!stall_mode) check(cycles-previous_acc_cycle==words_per_output,"no-stall output interval");
                    else begin
                        check(cycles-previous_acc_cycle>=words_per_output,"stalled output interval too short");
                        if(cycles-previous_acc_cycle>words_per_output) stretched_intervals=stretched_intervals+1;
                    end
                end
                pure_sum=$signed(acc);
                observed_with_bias=pure_sum+bias(layer,received);
                expected_with_bias=expected_acc_bias(received);
                if(observed_with_bias!==expected_with_bias) begin
                    if(mismatches<5)
                        $display("MISMATCH: case=%s output=%0d golden_expected=%0d ours_acc_plus_bias=%0d pure_acc=%0d bias=%0d",
                                 case_name,received,expected_with_bias,observed_with_bias,pure_sum,bias(layer,received));
                    mismatches=mismatches+1;
                end
                if(observed_with_bias!=golden(layer,received)) changed_outputs=changed_outputs+1;
                if(pure_sum<min_sum) min_sum=pure_sum;
                if(pure_sum>max_sum) max_sum=pure_sum;
                if(pure_sum<0) negative_count=negative_count+1;
                previous_acc_cycle=cycles; last_acc_cycle=cycles;
                received=received+1; outputs_checked=outputs_checked+1;
            end
            if(mac_done) begin
                check(!acc_valid,"done must be after final acc_valid");
                check(received==out_count && issued==total_words,"done before all inputs/outputs");
                check(cycles==last_acc_cycle+1,"mac_done not exactly one cycle after final valid");
            end
            previous_valid=acc_valid; previous_done=mac_done;
        end
    end

    task prepare_case(input integer which, input integer modification, input bit stalled, input string name);
        integer a,b,o,offset;
        begin
            layer=which;variant=modification;stall_mode=stalled;case_name=name;
            in_count=inputs(layer);out_count=outputs(layer);words_per_output=in_count/8;total_words=words_per_output*out_count;
            producer_on=0;empty_probe=stalled;produced=0;issued=0;received=0;
            full_cycles=0;stall_cycles=0;empty_attempts=0;busy_starts=0;stretched_intervals=0;
            changed_outputs=0;negative_count=0;min_sum=2147483647;max_sum=-2147483647;
            previous_valid=0;previous_done=0;mismatches=0;
            act_index=-1;weight_index=-1;change_delta=0;
            for(o=0;o<128;o=o+1) issue_end[o]=-100;
            for(a=0;a<in_count;a=a+1) activation[a]=activation_byte(layer,a);
            if(variant==1) begin
                // Select a byte that provably affects at least three outputs.
                for(a=0;a<in_count;a=a+1) begin
                    nonzero_count=0;
                    for(o=0;o<out_count;o=o+1)
                        if(blob[weight_offset(layer)+o*in_count+a]!=0) nonzero_count=nonzero_count+1;
                    if(act_index<0 && nonzero_count>=3) act_index=a;
                end
                check(act_index>=0,"no activation byte with three nonzero weights");
                change_delta=(s8(activation[act_index])==127) ? -1:1;
                activation[act_index]=s8(activation[act_index])+change_delta;
            end
            if(variant==2) begin
                for(a=0;a<in_count;a=a+1)
                    if(weight_index<0 && s8(activation[a])!=0) weight_index=5*in_count+a;
                check(weight_index>=0,"no nonzero activation for weight perturbation");
                change_delta=(s8(blob[weight_offset(layer)+weight_index])==127) ? -1:1;
            end
            if(variant>=3)
                for(a=0;a<in_count;a=a+1) activation[a]=8'h80;
            if(layer==0) begin
                for(a=0;a<384;a=a+1)
                    for(b=0;b<8;b=b+1) flat_mem[a][8*b +: 8]=activation[a*8+b];
            end else begin
                for(a=0;a<128;a=a+1) begin
                    @(negedge clk);hidden_we=1;hidden_wbank=(layer==2);hidden_waddr=a;hidden_wdata=activation[a];
                    @(posedge clk);#2;
                end
                @(negedge clk);hidden_we=0;
                // Use the real synchronous FCW RAM; only the chosen layer's
                // address range is written, at the specified global base.
                offset=(layer==2) ? 2048:0;
                for(a=0;a<total_words;a=a+1) begin
                    @(negedge clk);fcw_we=1;fcw_waddr=offset+a;fcw_wdata=weight_word(layer,a);
                    @(posedge clk);#2;
                end
                @(negedge clk);fcw_we=0;
            end
            if(layer==0) begin
                producer_on=1;
                while(!fifo_full) begin @(posedge clk);#2; end
                repeat(3) begin @(posedge clk);#2; end
                check(produced==512 && full_cycles>0,"real FIFO prefill/full backpressure was not exercised");
            end
        end
    endtask

    task execute_case;
        integer t;
        begin
            @(negedge clk);mac_sel=layer;mac_start=1;
            @(posedge clk);#2;start_cycle=cycles;collect=1;
            @(negedge clk);mac_start=0;mac_sel=(layer+1)%3;
            t=0;
            while(!mac_done && t<200000) begin
                @(posedge clk);#2;
                if(!mac_done) begin
                    @(negedge clk);
                    mac_start=(t==12); // Deliberate idle-only contract probe.
                    mac_sel=(layer+2)%3;
                end
                t=t+1;
            end
            check(mac_done,"layer timeout");
            check(mismatches==0,$sformatf("full accumulator compare mismatches=%0d",mismatches));
            check(busy_starts==1,"busy start probe not sampled exactly once");
            if(layer==0) check(produced==49152 && issued==49152 && fifo_empty,"FC1 stream incomplete");
            if(stall_mode) check(stall_cycles>0 && empty_attempts>0 && stretched_intervals>0,"FIFO empty/pause path not covered");
            if(variant==1) check(changed_outputs>=3,"activation mutation did not change three outputs");
            if(variant==2) check(changed_outputs==1,"one weight byte must change exactly one output");
            if(variant==0 && layer<2) check(negative_count>0,"signed negative sums absent");
            bound_margin=64'sd2147483647-max_sum;
            $display("PASS: %s layer=%0d outputs=%0d mismatch=0 tag_base=%0d interval=%0d stalled=%0d groups=%0d first_acc_after_start=%0d last_acc_after_start=%0d done_after_start=%0d done_gap=1 busy_start_ignored=%0d",
                     case_name,layer,received,layer*128,words_per_output,stall_mode,issued,first_acc_cycle-start_cycle,last_acc_cycle-start_cycle,cycles-start_cycle,busy_starts);
            $display("OBS: %s min_pure_sum=%0d max_pure_sum=%0d negative_outputs=%0d positive_i32_margin=%0d negative_i32_margin=%0d",
                     case_name,min_sum,max_sum,negative_count,bound_margin,64'sd2147483648+min_sum);
            if(layer==0)
                $display("PASS: %s FIFO words=49152 full_cycles=%0d empty_stall_cycles=%0d empty_read_probes=%0d stretched_intervals=%0d overflow=0",
                         case_name,full_cycles,stall_cycles,empty_attempts,stretched_intervals);
            if(variant==1 || variant==2)
                $display("PASS: Z6 %s activation_byte=%0d weight_byte=%0d delta=%0d changed_outputs=%0d exact_delta_compare=1",
                         case_name,act_index,weight_index,change_delta,changed_outputs);
            collect=0;producer_on=0;empty_probe=0;mac_start=0;cases=cases+1;
            @(posedge clk);#2;
            check(!mac_done && !acc_valid,"completion pulse must clear after one cycle");
            repeat(3) begin @(posedge clk);#2;check(!acc_valid && !mac_done && !fifo_re,"unexpected idle output"); end
        end
    endtask

    initial begin
        fd=$fopen("preflight_ok.txt","r");check(fd!=0,"SHA preflight guard missing; use F-02 host runner");
        count=$fscanf(fd,"%h",guard);$fclose(fd);check(count==1 && guard==32'hF02ACC01,"invalid SHA preflight guard");
        fd=$fopen("blob.bin","rb");check(fd!=0,"blob open");count=$fread(blob,fd);$fclose(fd);check(count==422992,"blob byte count");
        $readmemh("encoder_flat_u64.hex",flat_golden);
        $readmemh("fc1_gelu_i8.hex",hidden0_golden);$readmemh("fc2_gelu_i8.hex",hidden1_golden);
        $readmemh("fc1_acc_i32.hex",gold1);$readmemh("fc2_acc_i32.hex",gold2);$readmemh("fc3_acc_i32.hex",gold3);
        $display("PASS: preflight blob_bytes=%0d golden_outputs=280 activation_words=384+16+16 hash_guard=F02ACC01",count);
        repeat(2) @(posedge clk);
        @(negedge clk);rst_n=1;
        prepare_case(0,0,0,"Z1_FC1_golden");execute_case();
        prepare_case(1,0,0,"Z2_FC2_golden");execute_case();
        prepare_case(2,0,0,"Z3_FC3_golden");execute_case();
        $display("PASS: Z1-Z3 golden accumulator comparison outputs=280 mismatch=0 bias_added_only_in_TB=1");
        prepare_case(0,0,1,"Z5_FC1_empty_stalls");execute_case();
        prepare_case(0,1,0,"Z6_FC1_activation");execute_case();
        prepare_case(0,2,0,"Z6_FC1_weight");execute_case();
        prepare_case(1,1,0,"Z6_FC2_activation");execute_case();
        prepare_case(1,2,0,"Z6_FC2_weight");execute_case();
        prepare_case(2,1,0,"Z6_FC3_activation");execute_case();
        prepare_case(2,2,0,"Z6_FC3_weight");execute_case();
        prepare_case(0,3,0,"Z4_FC1_minus128_squared");execute_case();
        check(min_sum==50331648 && max_sum==50331648,"signed INT8 true upper bound");
        prepare_case(0,4,0,"Z4_FC1_signed_minimum");execute_case();
        check(min_sum==-49938432 && max_sum==-49938432,"signed INT8 lower bound");
        $display("PASS: F-02 ALL cases=%0d outputs_compared=%0d checks=%0d cycles=%0d",cases,outputs_checked,checks,cycles);
        $finish;
    end
endmodule
