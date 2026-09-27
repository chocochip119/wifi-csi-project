`timescale 1ns / 1ps

// L-03 retains L-01/L-02 checks; adds byte-scatter coverage and independent division-based TB golden.
module blob_decoder_fixture #(
    parameter VERSION_CHECK=1'b1,
    parameter [31:0] MAGIC=32'h36574c50,
    parameter [31:0] VERSION=32'd2,
    parameter [31:0] WORDS=32'd105748
)(input wire clk);
    reg rst_n=0, loader_start=0, ld_valid=0;
    reg [63:0] ld_data=0;
    wire loader_done,loader_err,ld_ready,cfg_ok;
    wire [31:0] output_scale_bits,pool_mult,pool_shift;
    wire conv_we;
    wire [8:0] conv_waddr;
    wire [127:0] conv_wdata;
    wire [15:0] conv_wstrb;
    wire param_we;
    wire [8:0] param_waddr;
    wire [95:0] param_wdata;
    wire [2:0] param_wstrb;
    wire lut_we;
    wire [9:0] lut_waddr;
    wire [7:0] lut_wdata;
    wire fcw_we;
    wire [11:0] fcw_waddr;
    wire [63:0] fcw_wdata;
    blob_decoder #(.EXPECTED_MAGIC(MAGIC),.EXPECTED_VERSION(VERSION),
        .EXPECTED_TOTAL_WORDS(WORDS),.CHECK_VERSION(VERSION_CHECK)) dut (
        .clk(clk),.rst_n(rst_n),.loader_start(loader_start),.loader_done(loader_done),.loader_err(loader_err),
        .ld_data(ld_data),.ld_valid(ld_valid),.ld_ready(ld_ready),.cfg_ok(cfg_ok),
        .output_scale_bits(output_scale_bits),.pool_mult(pool_mult),.pool_shift(pool_shift),
        .conv_we(conv_we),
        .conv_waddr(conv_waddr),
        .conv_wdata(conv_wdata),
        .conv_wstrb(conv_wstrb),
        .param_we(param_we),
        .param_waddr(param_waddr),
        .param_wdata(param_wdata),
        .param_wstrb(param_wstrb),
        .lut_we(lut_we),
        .lut_waddr(lut_waddr),
        .lut_wdata(lut_wdata),
        .fcw_we(fcw_we),
        .fcw_waddr(fcw_waddr),
        .fcw_wdata(fcw_wdata)
    );

    integer cycle=0, tests=0, case_id=-1, accepted=0, start_cycle=0, done_cycle=0, done_events=0;
    integer gap_cycles=0, work_remaining=0, processing_region=-1, ignored_starts=0;
    integer region_beats[0:10],region_cycles[0:10],region_low[0:10];
    integer first[0:10],length[0:10],cost[0:10];
    bit seen[0:3721];
    reg [63:0] words_seen[0:3721], last_accepted_data=0;
    bit observing=0,model_error=0,previous_done=0;
    integer fault=0,gap_mode=0,extra_mode=0;
    bit busy_start_test=0,unused_changed=0;
    reg signed [31:0] shift_value=32'sd31;
    reg [31:0] random_state=32'h431bad21;
    localparam [31:0] OUTPUT_BITS=32'h3bd997a8, MULT_BITS=32'h783b66b4;
    string case_name;
    reg [8:0] conv_raddr=0,enc_param_raddr=0,fc_param_raddr=327;
    reg [9:0] enc_lut_raddr=0,fc_lut_raddr=1023;
    reg [11:0] fcw_raddr=0;
    wire [127:0] conv_rdata;
    wire [95:0] enc_param_rdata,fc_param_rdata;
    wire [7:0] enc_lut_rdata,fc_lut_rdata;
    wire [63:0] fcw_rdata;
    conv_weight_ram conv_ram(.clk(clk),.conv_we(conv_we),.conv_waddr(conv_waddr),.conv_wdata(conv_wdata),.conv_wstrb(conv_wstrb),.conv_raddr(conv_raddr),.conv_rdata(conv_rdata));
    param_ram params(.clk(clk),.param_we(param_we),.param_waddr(param_waddr),.param_wdata(param_wdata),.param_wstrb(param_wstrb),.enc_param_raddr(enc_param_raddr),.fc_param_raddr(fc_param_raddr),.enc_param_rdata(enc_param_rdata),.fc_param_rdata(fc_param_rdata));
    gelu_lut_ram lut(.clk(clk),.lut_we(lut_we),.lut_waddr(lut_waddr),.lut_wdata(lut_wdata),.enc_lut_raddr(enc_lut_raddr),.fc_lut_raddr(fc_lut_raddr),.enc_lut_rdata(enc_lut_rdata),.fc_lut_rdata(fc_lut_rdata));
    fcw_ram weights(.clk(clk),.fcw_we(fcw_we),.fcw_waddr(fcw_waddr),.fcw_wdata(fcw_wdata),.fcw_raddr(fcw_raddr),.fcw_rdata(fcw_rdata));
    integer pbase[0:4],pcount[0:4],pfirst[0:4];
    integer shift_fault_layer=-1,shift_fault_half=0,shift_fault_beat=-1;
    integer error_at=4000,param_writes=0,fcw_writes=0,lut_writes=0;
    bit swapped=0;
    integer conv_writes=0,conv_duplicates=0;
    bit cseen[0:332][0:15];
    reg [127:0] conv_readback[0:332];
    bit pseen[0:327][0:2],fseen[0:2431],lseen[0:1023];
    initial begin
        pbase[0]=0;pcount[0]=16;pfirst[0]=94;
        pbase[1]=16;pcount[1]=32;pfirst[1]=694;
        pbase[2]=48;pcount[2]=128;pfirst[2]=742;
        pbase[3]=176;pcount[3]=128;pfirst[3]=2982;
        pbase[4]=304;pcount[4]=24;pfirst[4]=3558;
    end
    function automatic [7:0] conv_value(input integer layer,input integer n);
        conv_value=8'((n*37+(n/256)*11+layer*83)%256);
    endfunction
    // TB intentionally uses division/modulo, independently of RTL tap/oc counters.
    task automatic check_conv_contents(input integer limit,input bit require_coverage);
        integer layer,n,linear,mismatches,missing,bad_lane,bad_golden;
        reg [7:0] expected_byte;
        begin
            mismatches=0;missing=0;bad_golden=0;
            for(integer a=0;a<333;a=a+1) begin
                @(negedge clk);conv_raddr=9'(a);@(posedge clk);#2;
                conv_readback[a]=conv_rdata;
                for(integer lane=0;lane<16;lane=lane+1) begin
                    if(a<45) begin layer=1;n=lane*45+a;linear=n;end
                    else begin layer=2;n=(lane+(a>=189?16:0))*144+(a>=189?a-189:a-45);linear=720+n;end
                    if(linear<limit) begin
                        expected_byte=conv_value(layer,n);
                        if(conv_rdata[lane*8+:8]!==expected_byte) mismatches=mismatches+1;
                        if(require_coverage && !cseen[a][lane]) missing=missing+1;
                    end
                end
            end
            check(missing==0 && conv_duplicates==0,"Conv byte coverage: no holes or duplicate (word,lane) pairs");
            if(swapped) check(mismatches>0,"swapped payload must also fail full Conv data comparison");
            else check(mismatches==0,"Conv full/prefix readback equals independent (oc,tap) golden");
            $display("PASS: L-03 C1/C2/C5 CONV case=%0d bytes=%0d writes=%0d coverage_checked=%0d missing=%0d duplicates=%0d data_mismatches=%0d expected_negative=%0d",case_id,limit,conv_writes,require_coverage,missing,conv_duplicates,mismatches,swapped);
            if(limit==5328 && !swapped && case_id==0 && tests==0 && MAGIC==32'h36574c50 && VERSION_CHECK==1) begin
                for(integer b=0;b<720;b=b+1) begin
                    bad_lane=((b/8)*8)/45;
                    if(conv_readback[b%45][bad_lane*8+:8]!==conv_value(1,b)) bad_golden=bad_golden+1;
                end
                check(bad_golden==56,"C3 intentionally wrong same-lane-per-beat golden must detect all 56 wrong targets");
                $display("PASS: L-03 C3 EXPECTED_MISMATCH same_lane_per_beat_golden checked_bytes=720 wrong_targets=56 mismatches=%0d",bad_golden);
            end
            @(negedge clk);
        end
    endtask
    function automatic [31:0] parameter_value(input integer addr,input integer field);
        reg signed [31:0] v;
        begin
            if(field==0) v=32'h13570000 ^ (addr*131+17);
            else if(field==1) v=32'h86420000 ^ (addr*257+29);
            else begin
                v=(addr%95)-31;
                for(integer l=0;l<5;l=l+1) begin
                    if(addr==pbase[l]) v=-31;
                    if(addr==pbase[l]+pcount[l]-1) v=63;
                end
            end
            parameter_value=v;
        end
    endfunction
    function automatic [63:0] fcw_value(input integer addr);
        fcw_value={32'hface0000 ^ (32'(addr)*32'd257),32'h12340000 ^ (32'(addr)*32'd131)};
    endfunction
    function automatic [7:0] lut_value(input integer addr);
        lut_value=8'((addr*37+addr/256*11+3)%256);
    endfunction
    // Independent layer arrays describe the expected blob, not RTL range branches.
    function automatic [63:0] data_word(input integer index);
        reg [63:0] v;
        integer b,addr;
        begin
            v={32'h86420000 ^ (32'(index)*3),32'h13570000 ^ 32'(index)};
            if(index>=4 && index<94)
                for(integer k=0;k<8;k=k+1) v[k*8+:8]=conv_value(1,(index-4)*8+k);
            if(index>=118 && index<694)
                for(integer k=0;k<8;k=k+1) v[k*8+:8]=conv_value(2,(index-118)*8+k);
            for(integer l=0;l<5;l=l+1)
                for(integer f=0;f<3;f=f+1) begin
                    b=index-pfirst[l]-f*(pcount[l]/2);
                    if(b>=0 && b<pcount[l]/2) begin
                        addr=pbase[l]+b*2;
                        v={parameter_value(addr+1,f),parameter_value(addr,f)};
                    end
                end
            if(index>=934 && index<2982) v=fcw_value(index-934);
            if(index>=3174 && index<3558) v=fcw_value(2048+index-3174);
            if(index>=3594 && index<3722)
                for(integer k=0;k<8;k=k+1) v[k*8+:8]=lut_value((index-3594)*8+k);
            data_word=v;
        end
    endfunction
    task check_ram_contents;
        integer pm,fm,lm;
        reg [95:0] pv;
        begin
            pm=0;fm=0;lm=0;
            check_conv_contents(5328,conv_writes==5328);
            for(integer a=0;a<328;a=a+1) begin
                @(negedge clk);enc_param_raddr=9'(a);fc_param_raddr=9'(327-a);
                @(posedge clk);#2;
                pv={parameter_value(a,2),parameter_value(a,1),parameter_value(a,0)};
                for(integer f=0;f<3;f=f+1) if(enc_param_rdata[f*32+:32]!==pv[f*32+:32]) pm=pm+1;
                check(enc_param_rdata===fc_param_rdata,"fixed encoder selection broadcasts one physical read result");
            end
            for(integer a=0;a<2432;a=a+1) begin
                @(negedge clk);fcw_raddr=12'(a);@(posedge clk);#2;
                if(fcw_rdata!==fcw_value(a)) fm=fm+1;
            end
            for(integer a=0;a<1024;a=a+1) begin
                @(negedge clk);enc_lut_raddr=10'(a);fc_lut_raddr=10'(1023-a);@(posedge clk);#2;
                if(enc_lut_rdata!==lut_value(a)) lm=lm+1;
                check(enc_lut_rdata===fc_lut_rdata,"both logical LUT outputs share the encoder address");
            end
            if(swapped) begin
                check(pm>0 && fm>0 && lm>0,"negative swapped-word stimulus MUST be rejected by each full-data checker");
                $display("PASS: L-02 N3 EXPECTED_MISMATCH param_fields=%0d fcw_words=%0d lut_bytes=%0d checked=984/2432/1024 header_ok=1",pm,fm,lm);
            end else check(pm==0 && fm==0 && lm==0,"full address/value RAM comparison (no sampling)");
            $display("PASS: L-02 RAM_READBACK case=%0d negative=%0d param_addresses=328 fields=984 fcw_words=2432 lut_bytes=1024 conv_checked_bytes=5328 mismatches=%0d",case_id,swapped,pm+fm+lm);
            @(negedge clk);
        end
    endtask
    task monitor_writes;
        integer field,layer,n,addr,lane,source_n;
        reg [127:0] expected_bus;
        begin
            if(conv_we) begin
                layer=conv_writes<720?1:2;n=conv_writes<720?conv_writes:conv_writes-720;
                check(conv_writes<5328,"no extra Conv write after full payload");
                addr=layer==1?n%45:45+(n/144/16)*144+n%144;
                lane=layer==1?n/45:(n/144)%16;
                check(conv_waddr==addr && conv_wstrb==(16'h1<<lane),"every Conv byte hits the formula's word and exactly one lane");
                if(cseen[addr][lane]) conv_duplicates=conv_duplicates+1;
                check(!cseen[addr][lane],"duplicate Conv (word,lane) write");
                source_n=swapped?(n/8)*8+((n%8)^4):n;
                expected_bus=0;expected_bus[lane*8+:8]=conv_value(layer,source_n);
                check(conv_wdata===expected_bus,"correct source byte and lane placement, other lanes zero");
                cseen[addr][lane]=1;conv_writes=conv_writes+1;
                if(tests==0 && case_id==0 && MAGIC==32'h36574c50 && VERSION_CHECK==1) begin
                    if(layer==1 && ((n>=40 && n<=47) || (n>=88 && n<=95) || (n>=128 && n<=135)))
                        $display("PASS: L-03 C3 BYTE beat=%0d k=%0d n=%0d word=%0d lane=%0d byte=%02h",4+n/8,n%8,n,addr,lane,conv_value(layer,n));
                    if((layer==1 && n==719) || (layer==2 && (n==0 || n==2303 || n==2304 || n==4607)))
                        $display("PASS: L-03 C4 BOUNDARY layer=%0d n=%0d word=%0d lane=%0d",layer,n,addr,lane);
                end
            end
            if(model_error) check(!conv_we && !param_we && !fcw_we && !lut_we,"no writes on the detected-error edge or later drain");
            check(int'(conv_we)+int'(param_we)+int'(fcw_we)+int'(lut_we)<=1,"at most one scheduled write per clock");
            if(param_we) begin
                check(param_waddr<328 && (param_wstrb==1 || param_wstrb==2 || param_wstrb==4),"Param address and one field strobe");
                field=param_wstrb==1?0:(param_wstrb==2?1:2);
                check(!pseen[param_waddr][field],"each field at each address written once per LOAD");
                check(^param_wdata[field*32+:32]!==1'bx,"Param selected field known");
                pseen[param_waddr][field]=1;param_writes=param_writes+1;
            end
            if(fcw_we) begin
                check(fcw_waddr<2432 && !fseen[fcw_waddr] && ^fcw_wdata!==1'bx,"unique known FCW write");
                fseen[fcw_waddr]=1;fcw_writes=fcw_writes+1;
            end
            if(lut_we) begin
                check(!lseen[lut_waddr] && ^lut_wdata!==1'bx,"unique known LUT write");
                lseen[lut_waddr]=1;lut_writes=lut_writes+1;
            end
        end
    endtask



    initial begin
        first[0]=0;length[0]=4;cost[0]=1;
        first[1]=4;length[1]=90;cost[1]=8;
        first[2]=94;length[2]=24;cost[2]=2;
        first[3]=118;length[3]=576;cost[3]=8;
        first[4]=694;length[4]=48;cost[4]=2;
        first[5]=742;length[5]=192;cost[5]=2;
        first[6]=934;length[6]=2048;cost[6]=1;
        first[7]=2982;length[7]=192;cost[7]=2;
        first[8]=3174;length[8]=384;cost[8]=1;
        first[9]=3558;length[9]=36;cost[9]=2;
        first[10]=3594;length[10]=128;cost[10]=8;
    end
    function automatic integer region_for(input integer index);
        integer result;
        begin
            result=15;
            for(integer j=0;j<11;j=j+1)
                if(index>=first[j] && index<first[j]+length[j]) result=j;
            region_for=result;
        end
    endfunction
    function automatic [63:0] stream_word(input integer index);
        reg [31:0] low_word,high_word;
        reg [63:0] pair;
        begin
            pair=data_word(index);low_word=pair[31:0];high_word=pair[63:32];
            if(index==shift_fault_beat) begin
                if(shift_fault_half==0) low_word=-32; else high_word=64;
            end
            case(index)
                0:begin low_word=fault==1?(MAGIC^32'h1):MAGIC;high_word=fault==2?(VERSION^32'h1):VERSION;end
                1:begin low_word=fault==3?(WORDS+1):WORDS;high_word=unused_changed?32'hdeadbeef:32'h3cb76adb;end
                2:begin low_word=OUTPUT_BITS;high_word=MULT_BITS;end
                3:begin low_word=shift_value;high_word=unused_changed?32'hffffffff:32'h0;end
                default:begin end
            endcase
            stream_word=(swapped && index>=4)?{low_word,high_word}:{high_word,low_word};
        end
    endfunction
    task automatic check(input bit condition,input string message);
        if(!condition) begin
            $display("FAIL: L-01 %s case=%0d cycle=%0d count=%0d state=%0d %s",
                case_name,case_id,cycle,dut.beat_count_reg,dut.state_reg,message);
            $fatal(1,"blob decoder mismatch");
        end
    endtask

    always @(posedge clk) begin : scoreboard
        integer before_count,selected_region,predicted_count;
        bit fire,was_receiving,header_failure;
        cycle=cycle+1;
        if(!rst_n) check(!conv_we,"control reset suppresses Conv writes");
        if(!rst_n) begin
            previous_done=0;
            #1;
            check(!cfg_ok && !loader_done && !loader_err && !ld_ready && dut.beat_count_reg==0 &&
                {output_scale_bits,pool_mult,pool_shift}==='0,"synchronous reset clears control/header registers");
        end else begin
            check(!(previous_done && loader_done),"done width exactly one cycle");
            check(loader_done || !loader_err,"err is valid only with the done pulse");
            previous_done=loader_done;
            if(observing) begin
                before_count=dut.beat_count_reg;predicted_count=before_count;
                fire=ld_valid && ld_ready;was_receiving=(dut.state_reg==1);
                // A new START replaces the previous LOAD's retained terminal count.
                if(!(loader_start && dut.state_reg==0)) begin
                    check(before_count==accepted,"counter agrees with independent accepted-beat count");
                    check(dut.region_code==region_for(accepted),"region decode including every boundary and terminal count");
                end
                if(loader_start && dut.state_reg==0) begin
                    start_cycle=cycle;predicted_count=0;
                end else if(accepted<3722 || work_remaining>0) begin
                    if(loader_start) ignored_starts=ignored_starts+1;
                    if(work_remaining>0) begin
                        check(!ld_ready && !fire && dut.state_reg==2 && dut.work_left_reg==work_remaining,
                            "exact N-1 low READY cycles after each accepted beat");
                        check(dut.processing_region_reg==processing_region && dut.beat_data_reg===last_accepted_data,
                            "processing region and all 64 data bits held across subcycles");
                        if(accepted==3722 && ld_valid) model_error=1;
                        region_cycles[processing_region]=region_cycles[processing_region]+1;
                        region_low[processing_region]=region_low[processing_region]+1;
                        work_remaining=work_remaining-1;
                    end else begin
                        check(ld_ready,"ready returns high after all scheduled work");
                        if(!ld_valid) gap_cycles=gap_cycles+1;
                    end
                    if(fire) begin
                        check(accepted<3722 && !seen[accepted],"each index 0..3721 accepted exactly once");
                        selected_region=region_for(accepted);
                        check(dut.region_writes==cost[selected_region],"region write cost matches independent table");
                        check(ld_data===stream_word(accepted),"full source word sequence remains ordered");
                        seen[accepted]=1;words_seen[accepted]=ld_data;
                        region_beats[selected_region]=region_beats[selected_region]+1;
                        region_cycles[selected_region]=region_cycles[selected_region]+1;
                        header_failure=(accepted==0 && (fault==1 || (fault==2 && VERSION_CHECK))) ||
                            (accepted==1 && fault==3) || (accepted==3 && (shift_value < -31 || shift_value > 63)) || accepted==shift_fault_beat;
                        if(header_failure) model_error=1;
                        work_remaining=model_error?0:cost[selected_region]-1;
                        processing_region=selected_region;last_accepted_data=ld_data;
                        accepted=accepted+1;predicted_count=before_count+1;
                    end
                    if(model_error && accepted<3722) check(work_remaining==0,"header failure schedules no RAM work");
                end else check(!ld_ready,"terminal/idle cannot accept an extra beat");
                monitor_writes;
                #1;
                check(dut.beat_count_reg==predicted_count,"count only changes on START or VALID&&READY");
                if(fire && was_receiving) check(dut.beat_data_reg===last_accepted_data,"64-bit beat captured exactly once");
                if(loader_start && start_cycle==cycle) check(!cfg_ok && !loader_done && !loader_err,"accepted START invalidates old configuration");
                if(loader_done) begin
                    done_events=done_events+1;done_cycle=cycle;
                    check(accepted==3722 && work_remaining==0,"done only after last beat finishes all work");
                    check(loader_err===model_error && cfg_ok===!model_error,"done/err/cfg reflect final result together");
                end else if(accepted>0) check(!cfg_ok,"cfg remains invalid until whole LOAD succeeds");
            end
        end
    end

    task reset_fixture;
        begin
            @(negedge clk);observing=0;rst_n=0;loader_start=0;ld_valid=0;
            repeat(2) @(negedge clk);
            check(dut.state_reg==0 && !cfg_ok && dut.beat_count_reg==0,"reset returns idle and invalidates config");
            rst_n=1;
        end
    endtask
    task begin_load;
        begin
            accepted=0;start_cycle=0;done_cycle=0;done_events=0;gap_cycles=0;work_remaining=0;
            ignored_starts=0;model_error=0;processing_region=-1;
            param_writes=0;fcw_writes=0;lut_writes=0;conv_writes=0;conv_duplicates=0;
            for(integer a=0;a<333;a=a+1) for(integer lane=0;lane<16;lane=lane+1) cseen[a][lane]=0;
            for(integer a=0;a<328;a=a+1) for(integer f=0;f<3;f=f+1) pseen[a][f]=0;
            for(integer a=0;a<2432;a=a+1) fseen[a]=0;
            for(integer a=0;a<1024;a=a+1) lseen[a]=0;
            for(integer j=0;j<11;j=j+1) begin region_beats[j]=0;region_cycles[j]=0;region_low[j]=0;end
            for(integer j=0;j<3722;j=j+1) seen[j]=0;
            check(!ld_ready,"idle READY=0 before start");
            observing=1;loader_start=1;
            @(posedge clk);#2;
            check(dut.state_reg==1 && !cfg_ok && dut.beat_count_reg==0,"START enters receive at beat zero");
            @(negedge clk);loader_start=0;
        end
    endtask
    // Called and returned on a falling edge. Consecutive 1-cycle regions have
    // no accidental test-driver bubble; a stalled valid/data is held until fire.
    task automatic send_beat(input integer index);
        integer gap;
        begin
            gap=0;
            if(gap_mode==1 && index%17==0) gap=3;
            if(gap_mode==1 && index==742) gap=53;
            if(gap_mode==2) begin
                random_state=random_state^(random_state<<13);
                random_state=random_state^(random_state>>17);
                random_state=random_state^(random_state<<5);
                gap=random_state%5;
                if(index==742) gap=101;
            end
            ld_valid=0;
            repeat(gap) @(negedge clk);
            ld_data=stream_word(index);ld_valid=1;
            if(busy_start_test && (index==4 || index==95 || index==934)) loader_start=1;
            while(accepted<=index) begin
                @(posedge clk);#2;check(cycle-start_cycle<40000,"bounded beat acceptance");
                @(negedge clk);loader_start=0;
            end
            ld_valid=0;
        end
    endtask
    task finish_load;
        integer expected_cycles,region_work,expected_conv;
        bit want_error;
        begin
            // Extra VALID is an offered 3723rd beat, not a false handshake.
            if(extra_mode==1) begin
                ld_valid=1;ld_data=64'hcafef00d01234567;
            end else if(extra_mode==2) begin
                repeat(6) @(negedge clk);
                ld_valid=1;ld_data=64'hbad0beef12345678;
            end
            while(!loader_done) begin
                @(posedge clk);#2;check(cycle-start_cycle<40000,"bounded completion including final work");
            end
            want_error=fault==1 || (fault==2 && VERSION_CHECK) || fault==3 || shift_value < -31 || shift_value > 63 || extra_mode!=0 || shift_fault_layer>=0;
            check(loader_err==want_error && cfg_ok==!want_error && done_events==1,"one correct result per LOAD");
            check(accepted==3722 && dut.beat_count_reg==3722,"exact accepted count, including overlength offer");
            region_work=0;
            for(integer j=0;j<11;j=j+1) begin
                check(region_beats[j]==length[j],"complete count in every one of eleven regions");
                expected_cycles=0;
                for(integer b=first[j];b<first[j]+length[j];b=b+1) expected_cycles=expected_cycles+(b>=error_at?1:cost[j]);
                check(region_cycles[j]==expected_cycles && region_low[j]==expected_cycles-length[j],"each region exact processing and low-READY total");
                region_work=region_work+region_cycles[j];
                $display("PASS: L-01 REGION case=%0d region=%0d first=%0d last=%0d beats=%0d work_cycles=%0d ready_low=%0d",
                    case_id,j,first[j],first[j]+length[j]-1,region_beats[j],region_cycles[j],region_low[j]);
            end
            check(done_cycle-start_cycle==region_work+gap_cycles,"total latency equals independent region cost plus supply gaps");
            for(integer j=0;j<3722;j=j+1) check(seen[j] && words_seen[j]===stream_word(j),"all accepted indexes/data, no sample-only check");
            if(!want_error) check({output_scale_bits,pool_mult,pool_shift}==={OUTPUT_BITS,MULT_BITS,shift_value},"header word4/5/6 bit-exact little-endian mapping");
            if(busy_start_test) check(ignored_starts==3,"three busy START pulses ignored without counter/data reset");
            $display("PASS: L-01 CASE id=%0d name=%s version_check=%0d accepted=%0d work=%0d supply_wait=%0d total_cycles=%0d ready_low=%0d done_pulses=%0d error=%b cfg=%b ignored_START=%0d extra_offered=%0d",
                case_id,case_name,VERSION_CHECK,accepted,region_work,gap_cycles,done_cycle-start_cycle,region_work-3722,done_events,loader_err,cfg_ok,ignored_starts,extra_mode!=0);
            @(negedge clk);observing=0;ld_valid=0;
            repeat(2) begin @(posedge clk);#2;check(!loader_done && !loader_err && !ld_ready && cfg_ok==!want_error,"one-cycle result then sticky config, idle READY zero");end
            $display("PASS: L-02 WRITE_COUNTS case=%0d param=%0d fcw=%0d lut=%0d error_at=%0d no_write_after_error=PASS",case_id,param_writes,fcw_writes,lut_writes,error_at);
            expected_conv=error_at<4?0:(error_at<118?720:5328);
            check(conv_writes==expected_conv,"Conv write count agrees with earliest detectable error location");
            if(want_error && conv_writes>0) check_conv_contents(conv_writes,1);
            if(!want_error) begin
                check(conv_writes==5328,"C1 all 5328 bytes written exactly once");
                check(param_writes==984 && fcw_writes==2432 && lut_writes==1024,"all expected write counts exact");
                check_ram_contents;
            end
            tests=tests+1;
            @(negedge clk);
        end
    endtask
    task automatic run_case(input integer id,input bit do_reset);
        begin
            case_id=id;case_name="";fault=0;gap_mode=0;extra_mode=0;busy_start_test=0;unused_changed=0;
            shift_value=31;shift_fault_layer=-1;shift_fault_half=0;shift_fault_beat=-1;swapped=0;error_at=4000;random_state=32'h431bad21;
            case(id)
                0:case_name="normal";
                1:begin case_name="source_gaps_and_read_boundary";gap_mode=1;end
                2:begin case_name="seeded_gaps";gap_mode=2;end
                3:begin case_name="bad_magic_drain";fault=1;end
                4:begin case_name="version_policy";fault=2;end
                5:begin case_name="bad_total_words_drain";fault=3;end
                6:begin case_name="shift_minus32";shift_value=-32;end
                7:begin case_name="shift_64";shift_value=64;end
                8:begin case_name="shift_minus31";shift_value=-31;end
                9:begin case_name="shift_63";shift_value=63;end
                10:begin case_name="ignored_word3_word7";unused_changed=1;end
                11:begin case_name="busy_START";busy_start_test=1;end
                12:begin case_name="extra_early_final_work";extra_mode=1;end
                13:begin case_name="extra_last_final_work";extra_mode=2;end
                14:begin case_name="bad_magic_with_gaps";fault=1;gap_mode=2;end
                15:begin case_name="shift_INT32_MIN";shift_value=32'sh80000000;end
                16:begin case_name="shift_INT32_MAX";shift_value=32'sh7fffffff;end
                17:begin case_name="swapped_payload_words_negative";swapped=1;end
                18,19,20,21,22,23,24,25,26,27: begin
                    shift_fault_layer=(id-18)/2;shift_fault_half=(id-18)%2;
                    shift_fault_beat=pfirst[shift_fault_layer]+pcount[shift_fault_layer];
                    if(shift_fault_half==1) shift_fault_beat=shift_fault_beat+pcount[shift_fault_layer]/2-1;
                    case_name=$sformatf("array_shift_layer%0d_half%0d",shift_fault_layer,shift_fault_half);
                end
                default:$fatal(1,"invalid CASE");
            endcase
            if(fault==1 || (fault==2 && VERSION_CHECK)) error_at=0;
            else if(fault==3) error_at=1;
            else if(shift_value < -31 || shift_value > 63) error_at=3;
            else if(shift_fault_layer>=0) error_at=shift_fault_beat;
            if(do_reset) reset_fixture;
            begin_load;
            for(integer j=0;j<3722;j=j+1) send_beat(j);
            finish_load;
        end
    endtask
    task reset_during_work;
        reg [11:0] held_count;
        begin
            case_id=17;case_name="reset_during_Conv1_work";fault=0;gap_mode=0;extra_mode=0;busy_start_test=0;
            reset_fixture;begin_load;
            for(integer j=0;j<5;j=j+1) send_beat(j);
            check(dut.state_reg==2 && dut.work_left_reg==7,"reset test is genuinely mid-processing");
            observing=0;held_count=dut.beat_count_reg;rst_n=0;
            #1;check(dut.state_reg==2 && dut.beat_count_reg==held_count,"active-low assertion does not reset before a rising edge");
            @(posedge clk);#2;check(dut.state_reg==0 && !cfg_ok && !loader_done && !loader_err && dut.beat_count_reg==0,"one covered edge clears partial LOAD");
            @(negedge clk);rst_n=1;
            $display("PASS: L-01 RESET interrupted_after_beats=5 synchronous_edge=PASS cfg=0 count=0");
            run_case(0,0);
        end
    endtask
    task idle_offer;
        begin
            reset_fixture;ld_valid=1;ld_data=64'hdeadbeef00112233;
            repeat(3) begin @(posedge clk);#2;check(!ld_ready && dut.beat_count_reg==0 && !loader_done && !cfg_ok,"idle offer is never accepted");end
            @(negedge clk);ld_valid=0;
            $display("PASS: L-01 IDLE offered_cycles=3 accepted=0 READY=0");
        end
    endtask
    task reset_preserves_loaded_rams;
        reg [95:0] preserved_word;
        begin
            // Enter the second Param write with deliberately corrupt pending data.
            // Reset must suppress it while retaining every previously loaded RAM word.
            case_id=28;case_name="reset_pending_param_preserves_RAM";
            begin_load;
            for(integer j=0;j<94;j=j+1) send_beat(j);
            // Finish all seven trailing Conv bytes before isolating the Param reset probe.
            while(!ld_ready) begin @(posedge clk);#2;@(negedge clk);end
            observing=0;
            ld_data={~parameter_value(1,0),parameter_value(0,0)};ld_valid=1;
            while(!ld_ready) @(negedge clk);
            @(posedge clk);#2;
            check(dut.state_reg==2 && dut.work_left_reg==1,"reset probe has a pending second Param write");
            preserved_word=params.mem[1];
            @(negedge clk);ld_valid=0;rst_n=0;
            @(posedge clk);#2;
            check(!param_we && params.mem[1]===preserved_word && !cfg_ok && dut.beat_count_reg==0,"reset suppresses pending corrupt write without clearing RAM");
            @(negedge clk);rst_n=1;
            check_ram_contents;
            $display("PASS: L-02 RESET_RAM pending_param_write=blocked preserved_fields=984 preserved_fcw=2432 preserved_lut=1024 cfg=0");
        end
    endtask
endmodule

// Deliberately no parameter override: this probe tests the RTL default itself.
module blob_default_version_probe(input wire clk);
    reg rst_n=0,loader_start=0,ld_valid=0;
    reg [63:0] ld_data=0;
    wire loader_done,loader_err,ld_ready,cfg_ok;
    integer accepted=0;
    blob_decoder dut(.clk(clk),.rst_n(rst_n),.loader_start(loader_start),.loader_done(loader_done),.loader_err(loader_err),
        .ld_data(ld_data),.ld_valid(ld_valid),.ld_ready(ld_ready),.cfg_ok(cfg_ok),
        .output_scale_bits(),.pool_mult(),.pool_shift(),.conv_we(),.conv_waddr(),.conv_wdata(),.conv_wstrb(),
        .param_we(),.param_waddr(),.param_wdata(),.param_wstrb(),.lut_we(),.lut_waddr(),.lut_wdata(),.fcw_we(),.fcw_waddr(),.fcw_wdata());
    task run;
        begin
            @(negedge clk);rst_n=0;
            @(negedge clk);rst_n=1;loader_start=1;
            @(negedge clk);loader_start=0;
            for(integer b=0;b<3722;b=b+1) begin
                ld_valid=1;ld_data=(b==0)?{32'd3,32'h36574c50}:64'd0;
                @(posedge clk);
                if(!ld_ready) $fatal(1,"FAIL: default version probe unexpectedly stalled");
                accepted=accepted+1;
                #2;
                if(b<3721 && loader_done) $fatal(1,"FAIL: default version probe early done");
                @(negedge clk);
            end
            ld_valid=0;
            if(!loader_done || !loader_err || cfg_ok || dut.CHECK_VERSION!=1 || dut.EXPECTED_VERSION!=2)
                $fatal(1,"FAIL: unmodified RTL default must reject version 3");
            $display("PASS: L-02 N7 RTL_DEFAULT no_parameter_override=1 CHECK_VERSION=1 EXPECTED_VERSION=2 blob_version=3 accepted=%0d done=1 err=1 cfg=0",accepted);
        end
    endtask
endmodule

module tb_blob_decoder;
    reg clk=0;
    always #5 clk=~clk;
    blob_decoder_fixture #(.VERSION_CHECK(1)) checked(clk);
    blob_decoder_fixture defaults(clk);
    blob_decoder_fixture #(.VERSION_CHECK(0)) optout(clk);
    blob_default_version_probe rtl_defaults(clk);
    blob_decoder_fixture #(.VERSION_CHECK(1),.MAGIC(32'h12345678),.VERSION(32'd17),.WORDS(32'd123456)) alternate(clk);
    integer selected=-1;
    initial begin #25000000;$fatal(1,"FAIL: L-01 global deadline");end
    initial begin
        if($value$plusargs("CASE=%d",selected)) begin
            if(selected<0 || selected>27) $fatal(1,"invalid CASE selector");
            checked.run_case(selected,1);
        end else begin
            checked.idle_offer;
            for(integer j=0;j<=27;j=j+1) checked.run_case(j,1);
            // Do not reset between these LOADs: prove cfg=1 -> START clears -> failure stays 0.
            checked.run_case(0,0);checked.run_case(3,0);checked.run_case(0,0);
            checked.reset_during_work;
            checked.reset_preserves_loaded_rams;
            rtl_defaults.run;
            defaults.run_case(4,1); // Default CHECK_VERSION=1 rejects version 3.
            optout.run_case(4,1); // Explicit override preserves the optional disabled check.
            alternate.run_case(0,1);alternate.run_case(4,0);alternate.run_case(5,0);
        end
        $display("PASS: L-03 ALL C1-C7 D1-D7 N1-N7 checked_runs=%0d default_runs=%0d alternate_runs=%0d optout_runs=%0d selector=%0d ideal_cycles=9772 RAM_writes=5328/984/2432/1024",
            checked.tests,defaults.tests,alternate.tests,optout.tests,selected);
        $finish;
    end
endmodule
