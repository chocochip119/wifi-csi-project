`timescale 1ns / 1ps

// E-01 simulation miter. Reference modules are generated in scratch directly
// from others/CNN_Encoder: timescale + unique module names only. All original
// logic is retained. Compile both sets and the production Loader with this TB.
module e01_buffer_case #(
    parameter W=64, R=8, BYTES=64, ID=0,
    parameter WA=$clog2(BYTES*8/W), RA=$clog2(BYTES*8/R)
)(input wire clk, output reg done);
    reg we=0;
    reg [WA-1:0] waddr=0;
    reg [RA-1:0] raddr=0;
    reg [W-1:0] wdata=0;
    wire [R-1:0] ref_data,new_data;
    reg [7:0] golden[0:BYTES-1];
    integer checks=0,collisions=0;
    reg [31:0] rng=32'h5839ac01+ID;
    Buffer_e01_ref #(.W_DATA_WIDTH(W),.R_DATA_WIDTH(R),.DEPTH_BYTE(BYTES)) u_ref
        (.clk(clk),.we(we),.waddr(waddr),.wdata(wdata),.raddr(raddr),.rdata(ref_data));
    Buffer #(.W_DATA_WIDTH(W),.R_DATA_WIDTH(R),.DEPTH_BYTE(BYTES)) u_new
        (.clk(clk),.we(we),.waddr(waddr),.wdata(wdata),.raddr(raddr),.rdata(new_data));
    function automatic [W-1:0] word_pattern(input integer a,input integer tag);
        for(integer b=0;b<W/8;b=b+1) word_pattern[b*8+:8]=8'((a*(W/8)+b)*37+tag*19+ID);
    endfunction
    task automatic transact(input bit wr,input integer wa,ra,input reg [W-1:0] data);
        reg [R-1:0] held_ref,held_new,expected;
        begin
            @(negedge clk);held_ref=ref_data;held_new=new_data;
            we=wr;waddr=WA'(wa);raddr=RA'(ra);wdata=data;
            for(integer b=0;b<R/8;b=b+1) expected[b*8+:8]=golden[ra*(R/8)+b];
            #2;
            if(ref_data!==held_ref || new_data!==held_new)
                $fatal(1,"FAIL: E01_BUFFER id=%0d read changed between edges",ID);
            @(posedge clk);#1;
            if(ref_data!==expected || new_data!==expected)
                $fatal(1,"FAIL: E01_BUFFER id=%0d check=%0d we=%b waddr=%0d raddr=%0d expected=%h ref=%h new=%h",
                    ID,checks,wr,wa,ra,expected,ref_data,new_data);
            if(wr) begin
                if(wa*(W/8)<(ra+1)*(R/8) && ra*(R/8)<(wa+1)*(W/8)) collisions=collisions+1;
                for(integer b=0;b<W/8;b=b+1) golden[wa*(W/8)+b]=data[b*8+:8];
            end
            checks=checks+1;
        end
    endtask
    initial begin
        done=0;
        for(integer a=0;a<BYTES*8/W;a=a+1) transact(1,a,0,word_pattern(a,0));
        for(integer a=0;a<BYTES*8/R;a=a+1) transact(0,0,a,'0);
        // Every narrow lane, both first/last addresses, and same-edge read-first.
        for(integer a=0;a<BYTES*8/R;a=a+1) transact(1,(a*(R/8))/(W/8),a,word_pattern(a,1));
        for(integer a=0;a<200;a=a+1) begin
            rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
            transact(a[0],int'(rng%32'(BYTES*8/W)),int'((rng>>8)%32'(BYTES*8/R)),word_pattern(a,2));
        end
        for(integer a=0;a<BYTES*8/R;a=a+1) transact(0,0,a,'0);
        @(negedge clk);we=0;done=1;
        $display("PASS: E-01 BUFFER id=%0d W=%0d R=%0d bytes=%0d checks=%0d read_first_collisions=%0d latency=1 lane_order=LSB_at_low_address mismatches=0",ID,W,R,BYTES,checks,collisions);
    end
endmodule

module tb_encoder_equiv;
    reg clk=0;
    always #5 clk=~clk;
    wire [4:0] buffer_tests_done;
    e01_buffer_case #(.W(64),.R(8),.BYTES(11520),.ID(0)) b0(clk,buffer_tests_done[0]);
    e01_buffer_case #(.W(8),.R(8),.BYTES(20480),.ID(1)) b1(clk,buffer_tests_done[1]);
    e01_buffer_case #(.W(8),.R(64),.BYTES(64),.ID(2)) b2(clk,buffer_tests_done[2]);
    e01_buffer_case #(.W(24),.R(8),.BYTES(60),.ID(3)) b3(clk,buffer_tests_done[3]);
    e01_buffer_case #(.W(64),.R(16),.BYTES(64),.ID(4)) b4(clk,buffer_tests_done[4]);

    reg rst_n=0,loader_rst_n=0,enc_start=0,in_we=0;
    reg [10:0] in_waddr=0;
    reg [63:0] in_wdata=0;
    reg [8:0] feat_raddr=0;
    wire ref_done,new_done;
    wire [8:0] ref_conv_addr,new_conv_addr,ref_param_addr,new_param_addr;
    wire [9:0] ref_lut_addr,new_lut_addr;
    wire [63:0] ref_feat,new_feat;
    wire [127:0] conv_data;
    wire [95:0] param_data,unused_fc_param;
    wire [7:0] lut_data,unused_fc_lut;
    wire [63:0] unused_fcw;
    wire [31:0] pool_mult,pool_shift,output_scale;
    reg loader_start=0,ld_valid=0;
    reg [63:0] ld_data=0;
    wire loader_done,loader_err,ld_ready,cfg_ok;

    // Identical RAM responses reach both Encoders. Every request address is
    // compared independently; the reference request drives the real RAM ports.
    weight_param_loader loader (
        .clk(clk),.rst_n(loader_rst_n),.loader_start(loader_start),
        .loader_done(loader_done),.loader_err(loader_err),.ld_valid(ld_valid),.ld_ready(ld_ready),.ld_data(ld_data),
        .cfg_ok(cfg_ok),.pool_mult(pool_mult),.pool_shift(pool_shift),.output_scale_bits(output_scale),
        .param_sel_fc(1'b0),.lut_sel_fc(1'b0),.conv_raddr(ref_conv_addr),.conv_rdata(conv_data),
        .enc_param_raddr(ref_param_addr),.enc_param_rdata(param_data),
        .enc_lut_raddr(ref_lut_addr),.enc_lut_rdata(lut_data),
        .fc_param_raddr(9'd0),.fc_param_rdata(unused_fc_param),
        .fc_lut_raddr(10'd0),.fc_lut_rdata(unused_fc_lut),.fcw_raddr(12'd0),.fcw_rdata(unused_fcw)
    );
    CNN_Encoder_e01_ref u_ref (
        .clk(clk),.rst_n(rst_n),.enc_start(enc_start),.enc_done(ref_done),
        .in_we(in_we),.in_waddr(in_waddr),.in_wdata(in_wdata),
        .conv_raddr(ref_conv_addr),.conv_rdata(conv_data),
        .enc_param_raddr(ref_param_addr),.enc_param_rdata(param_data),
        .enc_lut_raddr(ref_lut_addr),.enc_lut_rdata(lut_data),
        .pool_mult(pool_mult),.pool_shift(pool_shift),.feat_raddr(feat_raddr),.feat_rdata(ref_feat)
    );
    CNN_Encoder u_new (
        .clk(clk),.rst_n(rst_n),.enc_start(enc_start),.enc_done(new_done),
        .in_we(in_we),.in_waddr(in_waddr),.in_wdata(in_wdata),
        .conv_raddr(new_conv_addr),.conv_rdata(conv_data),
        .enc_param_raddr(new_param_addr),.enc_param_rdata(param_data),
        .enc_lut_raddr(new_lut_addr),.enc_lut_rdata(lut_data),
        .pool_mult(pool_mult),.pool_shift(pool_shift),.feat_raddr(feat_raddr),.feat_rdata(new_feat)
    );
    localparam FILE_BYTES=422992;
    reg [7:0] blob[0:FILE_BYTES-1];
    reg [63:0] input_words[0:1439];
    reg [63:0] first_features[0:383];
    integer cycle=0,case_id=-1,start_edge=-1,done_edge=-1,done_assert_edge=-1;
    integer compared=0,feat_unknown=0,feat_known=0,done_pulses=0,completed=0;
    integer total_compared=0,total_feature_words=0;
    bit comparing=0,scan_running=0;
    reg [31:0] rng=32'h6e01cafe;
    string blob_path;
    task automatic check(input bit ok,input string message);
        if(!ok) begin
            $display("FAIL: E-01 case=%0d cycle=%0d %s",case_id,cycle,message);
            $fatal(1,"Encoder equivalence or contract failed");
        end
    endtask
    function automatic [63:0] file_beat(input integer index);
        integer off;
        begin
            off=(index<742)?index*8:399152+(index-742)*8;
            for(integer b=0;b<8;b=b+1) file_beat[b*8+:8]=blob[off+b];
        end
    endfunction
    task load_blob;
        integer fd,n,extra,started;
        begin
            if(!$value$plusargs("BLOB=%s",blob_path))
                blob_path="D:/2609_final_project/wifi-csi-pose-main/HLS/pl_accel_v6/pl_accel_v6_weights.bin";
            fd=$fopen(blob_path,"rb");check(fd!=0,"open actual blob read-only");
            n=$fread(blob,fd);extra=$fgetc(fd);$fclose(fd);
            check(n==FILE_BYTES && extra==-1,"exact actual blob length");
            check(file_beat(0)==={32'd2,32'h36574c50},"actual magic and version");
            repeat(2) @(negedge clk);loader_rst_n=1;loader_start=1;
            @(posedge clk);#1;started=cycle;
            @(negedge clk);loader_start=0;
            for(integer b=0;b<3722;b=b+1) begin
                ld_data=file_beat(b);ld_valid=1;
                @(posedge clk);
                while(!ld_ready) begin @(posedge clk);end
                @(negedge clk);ld_valid=0;
            end
            while(!loader_done) begin @(negedge clk);check(cycle-started<12000,"Loader deadline");end
            check(!loader_err && cfg_ok && cycle-started==9772,"actual blob LOAD succeeds at original timing");
            $display("PASS: E-01 BLOB path=%s bytes=%0d LOAD_beats=3722 LOAD_cycles=%0d pool_mult=%08h pool_shift=%0d",blob_path,n,cycle-started,pool_mult,$signed(pool_shift));
        end
    endtask
    always @(negedge clk) if(scan_running) feat_raddr<=feat_raddr+1'b1;
    always @(posedge clk) begin
        cycle=cycle+1;
        if(comparing) begin
            if(enc_start) start_edge=cycle;
            if(ref_done) begin done_pulses=done_pulses+1;done_edge=cycle;end
            // Catch X in data actually consumed by MAC; X on unused reset or
            // unwritten feature addresses is compared separately with case equality.
            if(u_ref.u_conv_mac.s2_valid && !u_ref.u_conv_mac.s2_pad)
                check(!$isunknown({u_ref.u_conv_mac.act,u_new.u_conv_mac.act,conv_data}),"valid MAC activation/weights must be known");
            #1;
            if(ref_done && done_assert_edge<0) done_assert_edge=cycle;
            if(ref_done!==new_done) begin
                $display("MISMATCH signal=enc_done ref=%b new=%b",ref_done,new_done);check(0,"enc_done");
            end
            if(ref_conv_addr!==new_conv_addr) begin
                $display("MISMATCH signal=conv_raddr ref=%h new=%h",ref_conv_addr,new_conv_addr);check(0,"conv_raddr");
            end
            if(ref_param_addr!==new_param_addr) begin
                $display("MISMATCH signal=enc_param_raddr ref=%h new=%h",ref_param_addr,new_param_addr);check(0,"enc_param_raddr");
            end
            if(ref_lut_addr!==new_lut_addr) begin
                $display("MISMATCH signal=enc_lut_raddr ref=%h new=%h",ref_lut_addr,new_lut_addr);check(0,"enc_lut_raddr");
            end
            if(ref_feat!==new_feat) begin
                $display("MISMATCH signal=feat_rdata addr=%0d ref=%h new=%h",feat_raddr,ref_feat,new_feat);check(0,"feat_rdata");
            end
            if(u_ref.in_rdata!==u_new.in_rdata || u_ref.fmap1_rdata!==u_new.fmap1_rdata) begin
                $display("MISMATCH buffers input=%h/%h fmap=%h/%h",u_ref.in_rdata,u_new.in_rdata,u_ref.fmap1_rdata,u_new.fmap1_rdata);
                check(0,"both Buffer read outputs each cycle");
            end
            compared=compared+1;
            if($isunknown(ref_feat)) feat_unknown=feat_unknown+1;else feat_known=feat_known+1;
        end
    end
    task automatic make_input(input integer id);
        reg [63:0] v;
        begin
            rng=32'h6e01cafe;
            for(integer a=0;a<1440;a=a+1) begin
                v=0;
                for(integer b=0;b<8;b=b+1) begin
                    if(id==0) v[8*b+:8]=8'((a*8+b)*37+((a*8+b)/256)*11+19);
                    else begin
                        rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
                        v[8*b+:8]=rng[7:0];
                    end
                end
                input_words[a]=v;
            end
        end
    endtask
    task automatic run_encoder(input integer id);
        integer latency,different,nonzero;
        reg [63:0] held_ref,held_new;
        begin
            @(negedge clk);case_id=id;rst_n=0;enc_start=0;scan_running=0;
            repeat(3) @(negedge clk);rst_n=1;
            make_input(id);
            for(integer a=0;a<1440;a=a+1) begin
                @(negedge clk);in_we=1;in_waddr=11'(a);in_wdata=input_words[a];
            end
            @(negedge clk);in_we=0;
            compared=0;feat_unknown=0;feat_known=0;done_pulses=0;
            start_edge=-1;done_edge=-1;done_assert_edge=-1;feat_raddr=0;
            comparing=1;scan_running=1;enc_start=1;
            @(negedge clk);enc_start=0;
            while(done_edge<0) begin
                @(negedge clk);check(cycle-start_edge<1300000,"bounded complete Encoder run");
            end
            comparing=0;scan_running=0;
            latency=done_edge-start_edge;
            $display("OBS: E-01 ENCODER case=%0d pattern=%s seed=%08h sampled_done_cycles=%0d first_assert_cycles=%0d compared_cycles=%0d output_signals=5 output_bits=93 extra_buffer_signals=2 known_feat_samples=%0d unknown_feat_samples=%0d done_pulses=%0d mismatches=0",
                id,id==0?"deterministic":"xorshift32",id==0?32'd0:32'h6e01cafe,latency,done_assert_edge-start_edge,compared,feat_known,feat_unknown,done_pulses);
            check(done_pulses==1,"enc_done sampled exactly once");
            // The specification requests reporting any difference from its
            // 1,278,890 figure. Do not hide an elapsed/inclusive count mismatch.
            if(latency!=1278890)
                $display("OBS: E-01 CYCLE_DEFINITION case=%0d spec=1278890 elapsed_edges=%0d inclusive_edges=%0d original_and_new_finish_together=1",id,latency,compared);
            check(compared==latency+1,"compare every edge START through final write, inclusive");
            total_compared=total_compared+compared;
            different=0;nonzero=0;
            for(integer a=0;a<512;a=a+1) begin
                @(negedge clk);held_ref=ref_feat;held_new=new_feat;feat_raddr=9'(a);
                #2;check(ref_feat===held_ref && new_feat===held_new,"feature read holds before clock");
                @(posedge clk);#1;
                if(ref_feat!==new_feat) begin
                    $display("MISMATCH signal=final_feat addr=%0d ref=%h new=%h",a,ref_feat,new_feat);check(0,"feature full sweep");
                end
                if(a<384) begin
                    check(!$isunknown({ref_feat,new_feat}),"all 384 valid final feature words are known");
                    if(id==0) first_features[a]=ref_feat;
                    else if(first_features[a]!==ref_feat) different=different+1;
                    if(ref_feat!=0) nonzero=nonzero+1;
                end else check(ref_feat==={64{1'bx}} && new_feat==={64{1'bx}},"384..511 are outside original RAM, not valid features");
            end
            check(nonzero>0 && (id==0 || different>0),"nontrivial known output, random input changes features");
            total_feature_words=total_feature_words+384;
            $display("PASS: E-01 FEATURES case=%0d swept_addresses=512 valid_words=384 known_bytes=3072 out_of_range_X=128 nonzero_words=%0d changed_from_pattern0=%0d mismatches=0 latency=1",id,nonzero,different);
            completed=completed+1;
        end
    endtask
    initial begin #100000000;$fatal(1,"FAIL: E-01 global deadline");end
    initial begin
        load_blob;
        wait(&buffer_tests_done);
        run_encoder(0);run_encoder(1);
        $display("PASS: E-01 ALL cases=%0d full_run_compared_cycles=%0d output_signals_per_cycle=5 extra_buffer_signals_per_cycle=2 final_valid_feature_words=%0d buffer_variants=5 mismatches=0",completed,total_compared,total_feature_words);
        $finish;
    end
endmodule
