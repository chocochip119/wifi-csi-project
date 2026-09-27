`timescale 1ns / 1ps

// L-05: read the original binary; no converted data or golden file is required.
// +BLOB=<path> overrides the default reference path. No DUT hierarchy references.
// This checks serialization/layout and Loader RAM contents, not CNN inference.
module tb_loader_real_blob;
    localparam integer FILE_BYTES=422992, STREAM_BEATS=3722;
    reg clk=0,rst_n=0,loader_start=0,ld_valid=0;
    always #5 clk=~clk;
    reg [63:0] ld_data=0;
    wire loader_done,loader_err,ld_ready,cfg_ok;
    wire [31:0] pool_mult,pool_shift,output_scale_bits;
    reg [8:0] conv_raddr=0,enc_param_raddr=0,fc_param_raddr=327;
    reg [9:0] enc_lut_raddr=0,fc_lut_raddr=1023;
    reg [11:0] fcw_raddr=0;
    wire [127:0] conv_rdata;
    wire [95:0] enc_param_rdata,fc_param_rdata;
    wire [7:0] enc_lut_rdata,fc_lut_rdata;
    wire [63:0] fcw_rdata;
    weight_param_loader dut (
        .param_sel_fc(1'b0), .lut_sel_fc(1'b0),
        .clk(clk),.rst_n(rst_n),.loader_start(loader_start),
        .loader_done(loader_done),.loader_err(loader_err),
        .ld_data(ld_data),.ld_valid(ld_valid),.ld_ready(ld_ready),.cfg_ok(cfg_ok),
        .pool_mult(pool_mult),.pool_shift(pool_shift),.output_scale_bits(output_scale_bits),
        .conv_raddr(conv_raddr),.conv_rdata(conv_rdata),
        .enc_param_raddr(enc_param_raddr),.enc_param_rdata(enc_param_rdata),
        .fc_param_raddr(fc_param_raddr),.fc_param_rdata(fc_param_rdata),
        .enc_lut_raddr(enc_lut_raddr),.enc_lut_rdata(enc_lut_rdata),
        .fc_lut_raddr(fc_lut_raddr),.fc_lut_rdata(fc_lut_rdata),
        .fcw_raddr(fcw_raddr),.fcw_rdata(fcw_rdata)
    );

    reg [7:0] blob[0:FILE_BYTES-1];
    reg [127:0] gold_conv[0:332];
    reg [95:0] gold_param[0:327];
    reg [7:0] gold_lut[0:1023];
    reg [63:0] gold_fcw[0:2431];
    bit conv_seen[0:332][0:15];
    integer pbase[0:4],pcount[0:4],bias_off[0:4],mult_off[0:4],shift_off[0:4];
    string blob_path;
    integer cycle=0,accepted=0,remaining=0,ready_low=0,start_cycle=0,done_cycle=0,done_events=0;
    bit loading=0,previous_done=0;

    task automatic check(input bit ok,input string message);
        if(!ok) begin
            $display("FAIL: L-05 cycle=%0d accepted=%0d %s",cycle,accepted,message);
            $fatal(1,"reference blob verification failed; do not change RTL or contract to pass");
        end
    endtask
    // Explicit byte order: file byte 0 is the least significant byte.
    function automatic [31:0] word_at(input integer word_index);
        integer b;
        begin b=4*word_index;word_at={blob[b+3],blob[b+2],blob[b+1],blob[b]};end
    endfunction
    function automatic [63:0] beat_at(input integer byte_offset);
        reg [63:0] v;
        begin
            for(integer k=0;k<8;k=k+1) v[k*8+:8]=blob[byte_offset+k];
            beat_at=v;
        end
    endfunction
    function automatic integer stream_offset(input integer index);
        stream_offset=(index<742)?index*8:399152+(index-742)*8;
    endfunction
    function automatic integer beat_cost(input integer index);
        begin
            if((index>=4 && index<94) || (index>=118 && index<694) || index>=3594) beat_cost=8;
            else if(index<4 || (index>=934 && index<2982) || (index>=3174 && index<3558)) beat_cost=1;
            else beat_cost=2;
        end
    endfunction

    task read_binary;
        integer fd,read_count,extra;
        reg signed [31:0] ps;
        begin
            if(!$value$plusargs("BLOB=%s",blob_path))
                blob_path="D:/2609_final_project/wifi-csi-pose-main/HLS/pl_accel_v6/pl_accel_v6_weights.bin";
            fd=$fopen(blob_path,"rb");check(fd!=0,"open reference binary read-only");
            read_count=$fread(blob,fd);extra=$fgetc(fd);$fclose(fd);
            check(read_count==FILE_BYTES && extra==-1,"exact file length, no truncation or trailing byte");
            $display("PASS: L-05 B1 FILE path=%s bytes=%0d words=%0d trailing_bytes=0",blob_path,read_count,read_count/4);
            for(integer j=0;j<8;j=j+1) $display("OBS: L-05 HEADER word=%0d hex=%08h unsigned=%0d signed=%0d",j,word_at(j),word_at(j),$signed(word_at(j)));
            check(word_at(0)==32'h36574c50 && word_at(1)==2 && word_at(2)==105748,"magic/version/word count match full_pose.h and Loader");
            ps=$signed(word_at(6));check(ps>=-31 && ps<=63,"pool shift in [-31,63]");
            check(399152-5936==393216 && 128*3072==393216,"skipped range equals FC1 128 outputs x 3072 INT8 inputs");
            check(5936+23840==STREAM_BEATS*8 && 399152+23840==FILE_BYTES,"two LOAD ranges cover all resident data");
            check(stream_offset(741)==5928 && stream_offset(742)==399152 && stream_offset(3721)==422984,"boundary beat source offsets exact");
            $display("PASS: L-05 B2 first=[0,5936) second=[399152,422992) skipped=393216 FC1_bytes=393216 beats=3722 first_beats=742 second_beats=2980 even_word_low32=1");
        end
    endtask

    task make_golden;
        integer a,lane,missing,duplicates,invalid_shifts,sv,lo,hi;
        begin
            duplicates=0;missing=0;invalid_shifts=0;
            for(a=0;a<333;a=a+1) begin
                gold_conv[a]=0;
                for(lane=0;lane<16;lane=lane+1) conv_seen[a][lane]=0;
            end
            // Independent golden uses n/45 and n%45; RTL uses tap/oc counters.
            for(integer n=0;n<720;n=n+1) begin
                a=n%45;lane=n/45;
                if(conv_seen[a][lane]) duplicates=duplicates+1;
                conv_seen[a][lane]=1;gold_conv[a][lane*8+:8]=blob[32+n];
            end
            for(integer n=0;n<4608;n=n+1) begin
                a=45+((n/144)/16)*144+(n%144);lane=(n/144)%16;
                if(conv_seen[a][lane]) duplicates=duplicates+1;
                conv_seen[a][lane]=1;gold_conv[a][lane*8+:8]=blob[944+n];
            end
            for(a=0;a<333;a=a+1) for(lane=0;lane<16;lane=lane+1) if(!conv_seen[a][lane]) missing=missing+1;
            check(missing==0 && duplicates==0,"golden Conv address pairs cover all 5328 bytes exactly once");
            for(integer l=0;l<5;l=l+1) begin
                lo=2147483647;hi=-2147483647;
                for(integer i=0;i<pcount[l];i=i+1) begin
                    gold_param[pbase[l]+i]={word_at(shift_off[l]+i),word_at(mult_off[l]+i),word_at(bias_off[l]+i)};
                    sv=$signed(word_at(shift_off[l]+i));if(sv<lo) lo=sv;if(sv>hi) hi=sv;
                    if(sv < -31 || sv > 63) begin
                        $display("OBS: L-05 INVALID_SHIFT layer=%0d index=%0d blob_word=%0d byte_offset=%0d value=%0d",l,i,shift_off[l]+i,4*(shift_off[l]+i),sv);
                        invalid_shifts=invalid_shifts+1;
                    end
                end
                $display("OBS: L-05 B5 SHIFT layer=%0d count=%0d min=%0d max=%0d",l,pcount[l],lo,hi);
            end
            for(a=0;a<2432;a=a+1) gold_fcw[a]=beat_at(a<2048 ? 400688+8*a : 418608+8*(a-2048));
            for(a=0;a<1024;a=a+1) gold_lut[a]=blob[421968+a];
            $display("PASS: L-05 B3 SHIFT_SCAN checked=328 invalid=%0d",invalid_shifts);
            check(invalid_shifts==0,"actual layer shifts must satisfy the existing contract");
            $display("PASS: L-05 B4 GOLDEN conv_bytes=5328 param_fields=984 lut_bytes=1024 fcw_words=2432 conv_missing=%0d conv_duplicates=%0d",missing,duplicates);
        end
    endtask

    task automatic weight_statistics(input string name,input integer offset,input integer count);
        integer lo,hi,zeros,neg,pos,v;
        begin
            lo=127;hi=-128;zeros=0;neg=0;pos=0;
            for(integer i=0;i<count;i=i+1) begin
                v=$signed(blob[offset+i]);if(v<lo) lo=v;if(v>hi) hi=v;
                if(v==0) zeros=zeros+1;else if(v<0) neg=neg+1;else pos=pos+1;
            end
            $display("OBS: L-05 B5 WEIGHT name=%s offset=%0d count=%0d min=%0d max=%0d zeros=%0d negative=%0d positive=%0d",name,offset,count,lo,hi,zeros,neg,pos);
        end
    endtask
    task lut_statistics;
        integer inc,equal,dec,lo,hi,zeros,v,nxt,drop,max_drop,differences;
        begin
            for(integer t=0;t<4;t=t+1) begin
                inc=0;equal=0;dec=0;lo=127;hi=-128;zeros=0;max_drop=0;
                for(integer i=0;i<256;i=i+1) begin
                    v=$signed(blob[421968+t*256+i]);
                    if(v<lo) lo=v;if(v>hi) hi=v;if(v==0) zeros=zeros+1;
                    if(i<255) begin
                        nxt=$signed(blob[421968+t*256+i+1]);
                        if(nxt>v) inc=inc+1;else if(nxt==v) equal=equal+1;
                        else begin
                            dec=dec+1;drop=v-nxt;if(drop>max_drop) max_drop=drop;
                            $display("OBS: L-05 B5 LUT_DOWN table=%0d index=%0d q=%0d value=%0d next_value=%0d",t,i,i-128,v,nxt);
                        end
                    end
                end
                $display("OBS: L-05 B5 LUT table=%0d count=256 min=%0d max=%0d zeros=%0d rising=%0d equal=%0d falling=%0d max_drop=%0d",t,lo,hi,zeros,inc,equal,dec,max_drop);
            end
            for(integer a=0;a<4;a=a+1) for(integer b=a+1;b<4;b=b+1) begin
                differences=0;
                for(integer i=0;i<256;i=i+1) if(blob[421968+a*256+i]!==blob[421968+b*256+i]) differences=differences+1;
                $display("OBS: L-05 B5 LUT_PAIR a=%0d b=%0d different_bytes=%0d",a,b,differences);
            end
        end
    endtask

    always @(posedge clk) begin
        cycle=cycle+1;
        if(!rst_n) begin
            previous_done=0;
            #1;check({cfg_ok,loader_done,loader_err,ld_ready}===4'b0,"synchronous reset to idle");
        end else begin
            check(!(previous_done && loader_done),"single-cycle done");
            check(!loader_err || loader_done,"err only with done");previous_done=loader_done;
            if(loading) begin
                if(loader_start) start_cycle=cycle;
                else if(remaining>0) begin
                    check(!ld_ready,"normal region work holds READY low");remaining=remaining-1;ready_low=ready_low+1;
                end else if(accepted<STREAM_BEATS) begin
                    check(ld_ready && ld_valid,"continuous source accepted at each ready boundary");
                    check(ld_data===beat_at(stream_offset(accepted)),"source beat is exact file byte sequence");
                    remaining=beat_cost(accepted)-1;accepted=accepted+1;
                end else check(!ld_ready,"no extra accepted beat");
                #1;
                if(loader_done) begin
                    done_events=done_events+1;done_cycle=cycle;
                    check(accepted==STREAM_BEATS && remaining==0,"completion after last byte write");
                end
            end
        end
    end
    task automatic send_beat(input integer b);
        begin
            ld_data=beat_at(stream_offset(b));ld_valid=1;
            while(accepted<=b) begin
                @(posedge clk);#2;check(cycle-start_cycle<12000,"bounded real blob LOAD");
                @(negedge clk);
            end
            ld_valid=0;
        end
    endtask

    task readback_all;
        integer cm,pm,lm,fm,compared_conv,compared_param,compared_lut,compared_fcw;
        begin
            cm=0;pm=0;lm=0;fm=0;compared_conv=0;compared_param=0;compared_lut=0;compared_fcw=0;
            for(integer a=0;a<2432;a=a+1) begin
                @(negedge clk);
                conv_raddr=9'(a<333?a:0);enc_param_raddr=9'(a<328?a:0);fc_param_raddr=9'(a<328?327-a:327);
                enc_lut_raddr=10'(a<1024?a:0);fc_lut_raddr=10'(a<1024?1023-a:1023);fcw_raddr=12'(a);
                @(posedge clk);#2;
                if(a<333) for(integer lane=0;lane<16;lane=lane+1) begin
                    compared_conv=compared_conv+1;
                    if(conv_rdata[lane*8+:8]!==gold_conv[a][lane*8+:8]) begin
                        if(cm<16) $display("OBS: L-05 CONV_MISMATCH word=%0d lane=%0d expected=%02h got=%02h",a,lane,gold_conv[a][lane*8+:8],conv_rdata[lane*8+:8]);cm=cm+1;
                    end
                end
                if(a<328) for(integer f=0;f<3;f=f+1) begin
                    compared_param=compared_param+1;
                    if(enc_param_rdata[f*32+:32]!==gold_param[a][f*32+:32]) begin
                        if(pm<16) $display("OBS: L-05 PARAM_MISMATCH word=%0d field=%0d expected=%08h got=%08h",a,f,gold_param[a][f*32+:32],enc_param_rdata[f*32+:32]);pm=pm+1;
                    end
                end
                if(a<1024) begin compared_lut=compared_lut+1;if(enc_lut_rdata!==gold_lut[a]) lm=lm+1;end
                compared_fcw=compared_fcw+1;if(fcw_rdata!==gold_fcw[a]) fm=fm+1;
                check(fc_param_rdata===enc_param_rdata && fc_lut_rdata===enc_lut_rdata,"L-04 fixed Encoder selection broadcasts to both outputs");
            end
            $display("OBS: L-05 B4 READBACK conv_bytes=%0d param_fields=%0d lut_bytes=%0d fcw_words=%0d mismatches=%0d/%0d/%0d/%0d hierarchy_reads=0 clocks=2432",compared_conv,compared_param,compared_lut,compared_fcw,cm,pm,lm,fm);
            check(compared_conv==5328 && compared_param==984 && compared_lut==1024 && compared_fcw==2432,"full comparison counts");
            check(cm==0 && pm==0 && lm==0 && fm==0,"all four RAM contents equal file-derived independent golden");
            $display("PASS: L-05 B4 RAM_PORT_READBACK all_compared=1 mismatches=0");
        end
    endtask

    initial begin #1000000;$fatal(1,"FAIL: L-05 global deadline");end
    initial begin
        pbase[0]=0;pcount[0]=16;bias_off[0]=188;mult_off[0]=204;shift_off[0]=220;
        pbase[1]=16;pcount[1]=32;bias_off[1]=1388;mult_off[1]=1420;shift_off[1]=1452;
        pbase[2]=48;pcount[2]=128;bias_off[2]=99788;mult_off[2]=99916;shift_off[2]=100044;
        pbase[3]=176;pcount[3]=128;bias_off[3]=104268;mult_off[3]=104396;shift_off[3]=104524;
        pbase[4]=304;pcount[4]=24;bias_off[4]=105420;mult_off[4]=105444;shift_off[4]=105468;
        read_binary;make_golden;
        weight_statistics("Conv1",32,720);weight_statistics("Conv2",944,4608);
        weight_statistics("FC1",5936,393216);weight_statistics("FC2",400688,16384);weight_statistics("FC3",418608,3072);
        lut_statistics;
        repeat(2) @(negedge clk);rst_n=1;
        @(negedge clk);loader_start=1;loading=1;
        @(posedge clk);#2;check(ld_ready && !cfg_ok,"START opens Loader and invalidates config");
        @(negedge clk);loader_start=0;
        for(integer b=0;b<STREAM_BEATS;b=b+1) send_beat(b);
        while(!loader_done) begin @(posedge clk);#2;check(cycle-start_cycle<12000,"bounded final work");end
        $display("OBS: L-05 B3 RESULT beats=%0d cycles=%0d ready_low=%0d done_pulses=%0d done=%b err=%b cfg=%b",accepted,done_cycle-start_cycle,ready_low,done_events,loader_done,loader_err,cfg_ok);
        check(loader_done && !loader_err && cfg_ok && done_events==1,"actual reference blob LOAD succeeds without contract changes");
        check(done_cycle-start_cycle==9772 && ready_low==6050,"actual payload preserves nominal LOAD timing");
        check(output_scale_bits===word_at(4) && pool_mult===word_at(5) && pool_shift===word_at(6),"public header outputs bit-exact");
        @(negedge clk);loading=0;
        readback_all;
        check(cfg_ok && !loader_done && !loader_err && !ld_ready,"idle and sticky valid config after readback");
        $display("PASS: L-05 REAL_BLOB B1-B6 ALL bytes=422992 beats=3722 skipped_FC1_bytes=393216 done=1 err=0 cfg=1 RAM_mismatches=0 cycles=9772 ready_low=6050");
        $finish;
    end
endmodule
