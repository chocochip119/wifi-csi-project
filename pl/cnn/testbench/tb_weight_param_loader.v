`timescale 1ns / 1ps

// L-04/L-07: public-port tests only; no hierarchical reads, forces or RAM access.
// D09: independent address selections; selected data broadcasts to both consumers.
module tb_weight_param_loader;
    reg clk=0, rst_n=0, loader_start=0, ld_valid=0;
    always #5 clk=~clk;
    reg [63:0] ld_data=0;
    wire loader_done,loader_err,ld_ready,cfg_ok;
    wire [31:0] pool_mult,pool_shift,output_scale_bits;
    reg [8:0] conv_raddr=0,enc_param_raddr=0,fc_param_raddr=1;
    reg [9:0] enc_lut_raddr=0,fc_lut_raddr=1;
    reg [11:0] fcw_raddr=0;
    wire [127:0] conv_rdata;
    wire [95:0] enc_param_rdata,fc_param_rdata;
    wire [7:0] enc_lut_rdata,fc_lut_rdata;
    wire [63:0] fcw_rdata;
    reg param_sel_fc=0, lut_sel_fc=0;
    weight_param_loader dut (
        .param_sel_fc(param_sel_fc), .lut_sel_fc(lut_sel_fc),
        .clk(clk),.rst_n(rst_n),.loader_start(loader_start),
        .loader_done(loader_done),.loader_err(loader_err),
        .ld_data(ld_data),.ld_valid(ld_valid),.ld_ready(ld_ready),.cfg_ok(cfg_ok),
        .pool_mult(pool_mult),.pool_shift(pool_shift),.output_scale_bits(output_scale_bits),
        .conv_raddr(conv_raddr),.conv_rdata(conv_rdata),
        .enc_param_raddr(enc_param_raddr),.enc_param_rdata(enc_param_rdata),
        .enc_lut_raddr(enc_lut_raddr),.enc_lut_rdata(enc_lut_rdata),
        .fc_param_raddr(fc_param_raddr),.fc_param_rdata(fc_param_rdata),
        .fc_lut_raddr(fc_lut_raddr),.fc_lut_rdata(fc_lut_rdata),
        .fcw_raddr(fcw_raddr),.fcw_rdata(fcw_rdata)
    );

    integer first[0:10],length[0:10],cost[0:10];
    integer pbase[0:4],pcount[0:4],pfirst[0:4];
    integer region_beats[0:10],region_cycles[0:10],region_low[0:10];
    integer cycle=0,case_id=-1,pattern_seed=1,fault=0,error_at=4000;
    integer accepted=0,remaining=0,active_region=0,start_cycle=0,done_cycle=0,done_events=0;
    integer completed=0,read_passes=0;
    bit observing=0,previous_done=0;
    localparam [31:0] SCALE=32'h3bd997a8, MULT=32'h783b66b4;

    task automatic check(input bit ok,input string message);
        if(!ok) begin
            $display("FAIL: L-04 case=%0d cycle=%0d accepted=%0d %s",case_id,cycle,accepted,message);
            $fatal(1,"weight_param_loader boundary mismatch");
        end
    endtask
    function automatic integer region_for(input integer b);
        integer found;
        begin
            found=-1;
            for(integer j=0;j<11;j=j+1) if(b>=first[j] && b<first[j]+length[j]) found=j;
            region_for=found;
        end
    endfunction
    function automatic [7:0] conv_byte(input integer layer,input integer n,input integer seed);
        conv_byte=8'((n*37+(n/256)*11+layer*83+seed*19)%256);
    endfunction
    function automatic [31:0] param_field(input integer a,input integer f,input integer seed);
        begin
            case(f)
                0:param_field=32'h13570000 ^ (a*131+17+seed*1009);
                1:param_field=32'h86420000 ^ (a*257+29+seed*503);
                default:param_field=32'((a+seed)%95-31);
            endcase
        end
    endfunction
    function automatic [63:0] fcw_word(input integer a,input integer seed);
        fcw_word={32'hface0000 ^ 32'(a*257+seed*3001),32'h12340000 ^ 32'(a*131+seed*701)};
    endfunction
    function automatic [7:0] lut_byte(input integer a,input integer seed);
        lut_byte=8'((a*37+(a/256)*11+seed*17+3)%256);
    endfunction
    // Independent division-based golden, unlike RTL tap/oc counters.
    function automatic [127:0] conv_word(input integer a,input integer seed,input integer prefix_seed,input integer prefix_bytes);
        integer layer,n;
        reg [127:0] v;
        begin
            for(integer lane=0;lane<16;lane=lane+1) begin
                if(a<45) begin layer=1;n=lane*45+a;end
                else begin layer=2;n=(lane+(a>=189?16:0))*144+(a>=189?a-189:a-45);end
                v[lane*8+:8]=conv_byte(layer,n,(layer==1 && n<prefix_bytes)?prefix_seed:seed);
            end
            conv_word=v;
        end
    endfunction
    function automatic [63:0] stream_word(input integer b);
        integer k,a;
        reg [63:0] v;
        begin
            v=0;
            if(b>=4 && b<94) for(k=0;k<8;k=k+1) v[k*8+:8]=conv_byte(1,(b-4)*8+k,pattern_seed);
            if(b>=118 && b<694) for(k=0;k<8;k=k+1) v[k*8+:8]=conv_byte(2,(b-118)*8+k,pattern_seed);
            for(integer l=0;l<5;l=l+1) for(integer f=0;f<3;f=f+1) begin
                k=b-pfirst[l]-f*(pcount[l]/2);
                if(k>=0 && k<pcount[l]/2) begin
                    a=pbase[l]+k*2;v={param_field(a+1,f,pattern_seed),param_field(a,f,pattern_seed)};
                end
            end
            if(b>=934 && b<2982) v=fcw_word(b-934,pattern_seed);
            if(b>=3174 && b<3558) v=fcw_word(2048+b-3174,pattern_seed);
            if(b>=3594) for(k=0;k<8;k=k+1) v[k*8+:8]=lut_byte((b-3594)*8+k,pattern_seed);
            case(b)
                0:v={(fault==2?32'd3:32'd2),(fault==1?32'h36574c51:32'h36574c50)};
                1:v={32'h3cb76adb,32'd105748};
                2:v={MULT ^ 32'(pattern_seed),SCALE ^ 32'(pattern_seed)};
                3:v={32'b0,32'd31};
                default:begin end
            endcase
            if(fault==3 && b==726) v[31:0]=32'd64; // Conv2 first shift, outside [-31,63].
            stream_word=v;
        end
    endfunction

    always @(posedge clk) begin : boundary_monitor
        integer r;
        cycle=cycle+1;
        if(!rst_n) begin
            previous_done=0;
            #1;
            check({loader_done,loader_err,ld_ready,cfg_ok}===4'b0,"reset clears control to idle");
            check({pool_mult,pool_shift,output_scale_bits}===96'b0,"reset clears constants");
        end else begin
            check(!(previous_done && loader_done),"done is exactly one cycle");
            check(loader_done || !loader_err,"error is valid only with done");
            previous_done=loader_done;
            if(observing) begin
                if(loader_start) start_cycle=cycle;
                else if(remaining>0) begin
                    check(!ld_ready,"expected subcycle READY low");
                    region_cycles[active_region]=region_cycles[active_region]+1;
                    region_low[active_region]=region_low[active_region]+1;
                    remaining=remaining-1;
                end else if(accepted<3722) begin
                    check(ld_ready,"READY high exactly at next beat boundary");
                    check(ld_valid,"nominal stream supplies every available cycle");
                    if(ld_valid && ld_ready) begin
                        r=region_for(accepted);check(r>=0,"valid region");
                        check(ld_data===stream_word(accepted),"ordered source payload");
                        region_beats[r]=region_beats[r]+1;region_cycles[r]=region_cycles[r]+1;
                        remaining=(accepted>=error_at?1:cost[r])-1;
                        active_region=r;accepted=accepted+1;
                    end
                end else check(!ld_ready,"terminal cannot accept more beats");
                #1;
                if(loader_start) check(!cfg_ok && !loader_done && !loader_err,"START clears old result/config");
                if(loader_done) begin
                    done_events=done_events+1;done_cycle=cycle;
                    check(accepted==3722 && remaining==0,"done follows all beat work");
                    check(loader_err===(fault!=0) && cfg_ok===(fault==0),"result agrees with injected fault");
                end else check(!cfg_ok,"configuration invalid while LOAD is active");
            end
        end
    end

    task reset_control;
        begin
            @(negedge clk);observing=0;rst_n=0;loader_start=0;ld_valid=0;
            repeat(2) @(negedge clk);
            rst_n=1;
        end
    endtask
    task automatic begin_load(input integer id,input integer seed,input integer inject_fault);
        begin
            @(negedge clk);case_id=id;pattern_seed=seed;fault=inject_fault;
            error_at=(fault==3)?726:((fault==0)?4000:0);
            accepted=0;remaining=0;done_events=0;done_cycle=0;
            for(integer j=0;j<11;j=j+1) begin region_beats[j]=0;region_cycles[j]=0;region_low[j]=0;end
            check(!ld_ready && !loader_done,"idle before new START");
            observing=1;loader_start=1;
            @(posedge clk);#2;check(ld_ready && !cfg_ok,"start accepted next edge");
            @(negedge clk);loader_start=0;
        end
    endtask
    task automatic send_beat(input integer b);
        begin
            ld_data=stream_word(b);ld_valid=1;
            while(accepted<=b) begin
                @(posedge clk);#2;check(cycle-start_cycle<12000,"bounded transfer");
                @(negedge clk);
            end
            ld_valid=0;
        end
    endtask
    task finish_load;
        integer work_sum,low_sum,expected;
        begin
            while(!loader_done) begin @(posedge clk);#2;check(cycle-start_cycle<12000,"bounded completion");end
            check(done_events==1,"exactly one completion event");
            work_sum=0;low_sum=0;
            for(integer j=0;j<11;j=j+1) begin
                expected=0;
                for(integer b=first[j];b<first[j]+length[j];b=b+1) expected=expected+(b>=error_at?1:cost[j]);
                check(region_beats[j]==length[j] && region_cycles[j]==expected && region_low[j]==expected-length[j],"per-region timing unchanged");
                work_sum=work_sum+region_cycles[j];low_sum=low_sum+region_low[j];
                if(fault==0) $display("PASS: L-04 K5 REGION case=%0d region=%0d beats=%0d work_cycles=%0d ready_low=%0d",case_id,j,region_beats[j],region_cycles[j],region_low[j]);
            end
            check(done_cycle-start_cycle==work_sum,"START-to-done equals sum of region costs");
            if(fault==0) begin
                check(work_sum==9772 && low_sum==6050,"L-03 nominal timing preserved");
                check(pool_mult===(MULT ^ 32'(pattern_seed)) && output_scale_bits===(SCALE ^ 32'(pattern_seed)) && pool_shift===32'd31,"header outputs at block boundary");
            end
            $display("PASS: L-04 K2/K5/K6 LOAD case=%0d seed=%0d fault=%0d accepted=%0d cycles=%0d ready_low=%0d done_pulses=%0d err=%b cfg=%b",case_id,pattern_seed,fault,accepted,work_sum,low_sum,done_events,loader_err,cfg_ok);
            @(negedge clk);observing=0;
            repeat(2) begin @(posedge clk);#2;check(!loader_done && !loader_err && !ld_ready && cfg_ok===(fault==0),"result pulse ends and cfg sticks");end
            completed=completed+1;
        end
    endtask
    task automatic full_load(input integer id,input integer seed,input integer inject_fault);
        begin
            begin_load(id,seed,inject_fault);
            for(integer b=0;b<3722;b=b+1) send_beat(b);
            finish_load;
        end
    endtask

    // Parallel port sweep covers every physical word, and checks every output on
    // all 2432 clocks. Before the next edge none of the six outputs may change.
    task automatic read_all(input integer seed,input integer prefix_seed,input integer prefix_bytes);
        integer ca,pa,la,hold_checks;
        reg [399:0] old_outputs;
        reg [127:0] cv;
        reg [95:0] pv;
        reg [7:0] lv;
        begin
            hold_checks=0;
            for(integer a=0;a<2432;a=a+1) begin
                ca=a%333;pa=a%328;la=a%1024;
                @(negedge clk);
                old_outputs={conv_rdata,enc_param_rdata,fc_param_rdata,enc_lut_rdata,fc_lut_rdata,fcw_rdata};
                conv_raddr=9'(ca);enc_param_raddr=9'(pa);fc_param_raddr=9'((pa+137)%328);
                enc_lut_raddr=10'(la);fc_lut_raddr=10'((la+1)%1024);fcw_raddr=12'(a);
                #2;
                check({conv_rdata,enc_param_rdata,fc_param_rdata,enc_lut_rdata,fc_lut_rdata,fcw_rdata}===old_outputs,"all six outputs held before next rising edge");
                hold_checks=hold_checks+6;
                @(posedge clk);#2;
                cv=conv_word(ca,seed,prefix_seed,prefix_bytes);
                pv={param_field(pa,2,seed),param_field(pa,1,seed),param_field(pa,0,seed)};
                lv=lut_byte(la,seed);
                check(conv_rdata===cv && fcw_rdata===fcw_word(a,seed),"Conv/FCW full data at one-cycle read latency");
                check(enc_param_rdata===pv && fc_param_rdata===pv,"both Param outputs follow selected Encoder address");
                check(enc_lut_rdata===lv && fc_lut_rdata===lv,"both LUT outputs follow selected Encoder address");
                check(enc_param_rdata!=={param_field(fc_param_raddr,2,seed),param_field(fc_param_raddr,1,seed),param_field(fc_param_raddr,0,seed)},"FC Param address differs and is unselected");
                check(enc_lut_rdata!==lut_byte(fc_lut_raddr,seed),"FC LUT address differs and is unselected");
            end
            read_passes=read_passes+1;
            $display("PASS: L-04 K2/K3/K4 READ case=%0d seed=%0d partial_new_bytes=%0d conv_bytes=5328 param_fields=984 lut_bytes=1024 fcw_words=2432 mismatches=0 clocks=2432 six_port_checks=%0d preedge_hold_checks=%0d selected=ENC",case_id,seed,prefix_bytes,2432*6,hold_checks);
        end
    endtask

    // Alternate both address sources and all four independent select pairs.
    // Six outputs must hold before the edge and match the sampled addresses
    // immediately after that edge: neither combinational nor two-cycle reads.
    task check_selection;
        integer ca,pa,la,fa,mask;
        reg [399:0] held;
        reg [95:0] expected_param;
        begin
            mask=0;
            for(integer k=0;k<64;k=k+1) begin
                @(negedge clk);
                held={conv_rdata,enc_param_rdata,fc_param_rdata,enc_lut_rdata,fc_lut_rdata,fcw_rdata};
                param_sel_fc=k[0];lut_sel_fc=k[1];mask=mask | (1<<(k%4));
                ca=(k*7)%333;fa=(k*31)%2432;
                conv_raddr=9'(ca);fcw_raddr=12'(fa);
                enc_param_raddr=9'(k+1);fc_param_raddr=9'(k+138);
                enc_lut_raddr=10'(k*3+1);fc_lut_raddr=10'(k*3+2);
                pa=param_sel_fc?fc_param_raddr:enc_param_raddr;
                la=lut_sel_fc?fc_lut_raddr:enc_lut_raddr;
                #2;
                check({conv_rdata,enc_param_rdata,fc_param_rdata,enc_lut_rdata,fc_lut_rdata,fcw_rdata}===held,
                    "S1/S4 selector/address changes cannot change data before edge");
                @(posedge clk);#2;
                expected_param={param_field(pa,2,5),param_field(pa,1,5),param_field(pa,0,5)};
                check(enc_param_rdata===expected_param && fc_param_rdata===expected_param,
                    "S1 both Param outputs broadcast independently selected address");
                check(enc_lut_rdata===lut_byte(la,5) && fc_lut_rdata===lut_byte(la,5),
                    "S1 both LUT outputs broadcast independently selected address");
                check(conv_rdata===conv_word(ca,5,0,0) && fcw_rdata===fcw_word(fa,5),
                    "S4 Conv/FCW unchanged during selection switches");
            end
            check(mask==15,"S1 all four select combinations exercised");
            @(negedge clk);param_sel_fc=0;lut_sel_fc=0;
            $display("PASS: L-07 S1/S4 select_pairs=00,01,10,11 distinct_addresses=64 clocks=64 six_port_checks=384 preedge_hold_checks=384 mismatches=0 read_latency=1");
        end
    endtask

    initial begin #3000000;$fatal(1,"FAIL: L-04 global deadline");end
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
        pbase[0]=0;pcount[0]=16;pfirst[0]=94;
        pbase[1]=16;pcount[1]=32;pfirst[1]=694;
        pbase[2]=48;pcount[2]=128;pfirst[2]=742;
        pbase[3]=176;pcount[3]=128;pfirst[3]=2982;
        pbase[4]=304;pcount[4]=24;pfirst[4]=3558;
        reset_control;
        full_load(0,1,0);read_all(1,0,0);

        // Change the data, then interrupt the first Conv beat after 3 byte writes.
        // Previously stored RAM contents must survive, including the written prefix.
        begin_load(1,2,0);
        for(integer b=0;b<5;b=b+1) send_beat(b);
        repeat(2) @(negedge clk);
        observing=0;rst_n=0;ld_valid=1;ld_data=64'hffffffffffffffff;
        repeat(2) @(negedge clk);
        ld_valid=0;rst_n=1;
        read_all(1,2,3);
        check(!cfg_ok && !loader_done && !loader_err && !ld_ready,"mid-Conv reset remains idle through RAM reads");
        $display("PASS: L-04 K6 RESET accepted=5 conv_new_bytes=3 remaining_RAM_preserved=1 reset_edges=2 cfg=0 no_spurious_done=1");

        full_load(2,3,0);read_all(3,0,0);
        full_load(3,4,1);read_all(3,0,0); // Bad magic: no RAM overwrite.
        reset_control;
        full_load(4,4,2);read_all(3,0,0); // Default Decoder version check remains enabled.
        reset_control;
        full_load(5,4,3); // Shift error drains remaining stream without a deadlock.
        reset_control;
        full_load(6,5,0);read_all(5,0,0);
        check_selection;
        $display("PASS: L-04 K2-K6 ALL completed_LOADs=%0d aborted_LOADs=1 full_port_sweeps=%0d default_runs_all=1 hierarchy_reads=0 nominal_cycles=9772 ready_low=6050",completed,read_passes);
        $finish;
    end
endmodule
