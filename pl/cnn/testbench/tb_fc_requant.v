`timescale 1ns / 1ps

module tb_fc_requant;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, mac_start=0;
    reg [1:0] mac_sel=0;
    wire mac_done, acc_valid;
    wire signed [31:0] acc;
    wire [8:0] acc_tag, flat_raddr;
    wire [4:0] hidden_raddr;
    wire [11:0] fcw_raddr;
    reg [63:0] flat_rdata=0;
    wire [63:0] hidden_rdata, fcw_rdata, fifo_rdata;
    wire fifo_re, fifo_empty, fifo_full;
    reg fifo_we=0;
    reg [63:0] fifo_wdata=0;
    reg hidden_we=0, hidden_wbank=0;
    reg [7:0] hidden_waddr=0, hidden_wdata=0;
    reg fcw_we=0;
    reg [11:0] fcw_waddr=0;
    reg [63:0] fcw_wdata=0;
    reg param_we=0, param_verify=0;
    reg [8:0] param_waddr=0, verify_addr=0;
    reg [95:0] param_wdata=0;
    reg [2:0] param_wstrb=0;
    wire [8:0] fc_param_raddr;
    wire [95:0] fc_param_rdata, param_broadcast;
    wire [8:0] physical_raddr=param_verify ? verify_addr : fc_param_raddr;
    // Synthetic vectors use the SAME requant and physical Param RAM after
    // the real-MAC cases; they do not replace the end-to-end golden checks.
    reg direct_mode=0, direct_valid=0;
    reg signed [31:0] direct_acc=0;
    reg [8:0] direct_tag=0;
    wire [31:0] rq_acc=direct_mode ? direct_acc : acc;
    wire rq_acc_valid=direct_mode ? direct_valid : acc_valid;
    wire [8:0] rq_acc_tag=direct_mode ? direct_tag : acc_tag;
    wire [7:0] rq;
    wire rq_valid;
    wire [8:0] rq_tag;

    fc_mac mac (.*);
    fc1_weight_fifo weights_fifo (.*);
    hidden_buffer hidden (
        .clk(clk),.rst_n(rst_n),.hidden_we(hidden_we),.hidden_wbank(hidden_wbank),
        .hidden_waddr(hidden_waddr),.hidden_wdata(hidden_wdata),
        .hidden_rbank(hidden_raddr[4]),.hidden_raddr({1'b0,hidden_raddr[3:0]}),.hidden_rdata(hidden_rdata)
    );
    fcw_ram resident_weights (.*);
    // param_ram's physical read selector is its enc port (D09 mux lives
    // outside this RAM). Drive that port explicitly, not just the FC label.
    param_ram parameters_ram (
        .clk(clk),.param_we(param_we),.param_waddr(param_waddr),.param_wdata(param_wdata),.param_wstrb(param_wstrb),
        .enc_param_raddr(physical_raddr),.enc_param_rdata(param_broadcast),
        .fc_param_raddr(physical_raddr),.fc_param_rdata(fc_param_rdata)
    );
    requant_stage #(.TAG_WIDTH(9),.FC_MODE(1),.PARAM_BASE0(9'd48),.PARAM_BASE1(9'd176),.PARAM_BASE2(9'd304)) dut (
        .clk(clk),.rst_n(rst_n),.acc(rq_acc),.acc_valid(rq_acc_valid),.acc_tag(rq_acc_tag),
        .enc_param_raddr(fc_param_raddr),.enc_param_rdata(fc_param_rdata),.rq(rq),.rq_valid(rq_valid),.rq_tag(rq_tag)
    );

    reg [7:0] blob[0:422991];
    reg [63:0] flat_golden[0:383];
    reg [7:0] hidden0_golden[0:127], hidden1_golden[0:127];
    reg signed [31:0] gold1_acc[0:127], gold2_acc[0:127], gold3_acc[0:23];
    reg [7:0] gold1_rq[0:127], gold2_rq[0:127], gold3_rq[0:23];
    integer pbias[0:327], pmult[0:327], pshift[0:327];
    integer cycles=0, checks=0, cases=0, layer=0, variant=0, produced=0;
    integer accepted=0, received=0, total_compared=0, mismatches=0, changed=0;
    integer saturation=0, case_saturation=0, rq_min=127, rq_max=-127;
    integer source_cycle[0:511];
    integer due[0:4095], expected[0:4095], saved_tag[0:4095];
    integer saved_acc[0:4095], saved_mult[0:4095], saved_shift[0:4095];
    reg producer_on=0, collect=0;
    integer fd,n,a,b,o,c,k,addr,sel,idx,t,first_rq,last_rq,start_cycle;
    reg [31:0] guard;
    reg signed [63:0] raw, biased;
    string case_name="preflight";
    always @(posedge clk) flat_rdata<=flat_golden[flat_raddr];
    initial begin #15000000; $fatal(1,"FAIL: F-03a global timeout"); end

    task check(input bit ok,input string message);
        begin checks=checks+1; if(!ok) $fatal(1,"FAIL: %s cycle=%0d %s",case_name,cycles,message); end
    endtask
    function automatic integer s8(input [7:0] x);
        s8=(x>=128) ? integer'(x)-256 : integer'(x);
    endfunction
    function automatic integer outputs(input integer l);
        outputs=(l==2) ? 24:128;
    endfunction
    function automatic integer base(input integer l);
        case(l) 0:base=48; 1:base=176; default:base=304; endcase
    endfunction
    function automatic integer weight_offset(input integer l);
        case(l) 0:weight_offset=5936; 1:weight_offset=400688; default:weight_offset=418608; endcase
    endfunction
    function automatic integer blob_param(input integer l,input integer field,input integer index);
        integer p,count;
        begin
            case(l) 0:p=99788; 1:p=104268; default:p=105420; endcase
            count=outputs(l); p=4*(p+field*count+index);
            blob_param=$signed({blob[p+3],blob[p+2],blob[p+1],blob[p]});
        end
    endfunction
    function automatic integer golden_acc(input integer l,input integer index);
        case(l) 0:golden_acc=gold1_acc[index]; 1:golden_acc=gold2_acc[index]; default:golden_acc=gold3_acc[index]; endcase
    endfunction
    function automatic integer golden_rq(input integer l,input integer index);
        case(l) 0:golden_rq=s8(gold1_rq[index]); 1:golden_rq=s8(gold2_rq[index]); default:golden_rq=s8(gold3_rq[index]); endcase
    endfunction
    function automatic [63:0] weight_word(input integer l,input integer index);
        integer j,p;
        begin p=weight_offset(l)+index*8; for(j=0;j<8;j=j+1) weight_word[8*j +: 8]=blob[p+j]; end
    endfunction
    // Independent arithmetic: signed floor division, not the RTL's barrel
    // shift expression. The source C++ uses -half for negative products.
    function automatic signed [63:0] rounded(input signed [63:0] x,input integer bias,input integer mult,input integer shift);
        reg signed [63:0] p,denom;
        begin
            p=(x+bias)*mult;
            if(shift>0) begin
                denom=64'sd1<<shift;
                rounded=(p>=0) ? (p+denom/2)/denom : -((-p+denom/2+denom-1)/denom);
            end else rounded=p*(64'sd1<<(-shift));
        end
    endfunction
    function automatic integer saturated(input signed [63:0] x);
        saturated=(x>127) ? 127 : (x < -127) ? -127 : x;
    endfunction

    always @(negedge clk) begin
        fifo_we=0;
        if(rst_n && producer_on && produced<49152 && !fifo_full) begin
            fifo_we=1; fifo_wdata=weight_word(0,produced);
        end
    end
    // Check the Param address at its RAM sampling edge. An acc_valid
    // produced just AFTER edge E is sampled at E+1 and gives rq at E+4.
    always @(posedge clk) begin
        cycles=cycles+1;
        if(rst_n && producer_on && fifo_we) begin
            check(!fifo_full,"FIFO overflow"); produced=produced+1;
        end
        if(rst_n && collect && rq_acc_valid) begin
            sel=rq_acc_tag[8:7];idx=rq_acc_tag[6:0];addr=base(sel)+idx;
            check(sel<3 && idx<outputs(sel),"invalid FC tag at Param request");
            check(fc_param_raddr===addr,$sformatf("Param address tag=%03h expected=%0d got=%0d",rq_acc_tag,addr,fc_param_raddr));
            check(source_cycle[rq_acc_tag]==cycles-1,"acc valid source-to-request edge alignment");
            due[accepted]=source_cycle[rq_acc_tag]+4;
            saved_tag[accepted]=rq_acc_tag;saved_acc[accepted]=$signed(rq_acc);
            saved_mult[accepted]=pmult[addr];saved_shift[accepted]=pshift[addr];
            raw=rounded($signed(rq_acc),pbias[addr],pmult[addr],pshift[addr]);
            expected[accepted]=saturated(raw);
            if(raw>127 || raw < -127) case_saturation=case_saturation+1;
            if(!direct_mode) begin
                check(sel==layer && idx==accepted,"MAC output order/tag");
                biased=$signed(rq_acc)+64'(blob_param(layer,0,idx));
                check(biased===64'(golden_acc(layer,idx)),"MAC pure sum + original bias versus golden acc");
                if(variant==0) begin
                    check(expected[accepted]==golden_rq(layer,idx),"independent requant versus golden");
                end
            end
            accepted=accepted+1;
        end
        #1;
        if(rst_n && collect) begin
            if(!direct_mode && acc_valid) source_cycle[acc_tag]=cycles;
            if(received<accepted && cycles==due[received]) check(rq_valid,"rq_valid missing at fixed latency");
            if(rq_valid) begin
                check(received<accepted,"unexpected rq_valid");
                check(cycles==due[received],"acc_valid -> rq_valid must be exactly 4 cycles");
                check(rq_tag===saved_tag[received],"rq tag pipeline");
                if(s8(rq)!=expected[received] || (^rq)===1'bx) begin
                    if(mismatches<5) $display("MISMATCH: layer=%0d out_idx=%0d golden_expected=%0d ours=%0d acc=%0d mult=%0d shift=%0d",
                        saved_tag[received]/128+1,saved_tag[received]%128,expected[received],$signed(rq),saved_acc[received],saved_mult[received],saved_shift[received]);
                    mismatches=mismatches+1;
                end
                if(received==0) first_rq=cycles;
                last_rq=cycles;
                if(!direct_mode && s8(rq)!=golden_rq(layer,received)) changed=changed+1;
                if(s8(rq)<rq_min) rq_min=s8(rq); if(s8(rq)>rq_max) rq_max=s8(rq);
                received=received+1;total_compared=total_compared+1;
            end
        end
    end

    task put_param(input integer address,input integer bias,input integer mult,input integer shift);
        begin
            @(negedge clk);param_we=1;param_wstrb=7;param_waddr=address;param_wdata={shift[31:0],mult[31:0],bias[31:0]};
            @(posedge clk);#2;pbias[address]=bias;pmult[address]=mult;pshift[address]=shift;
            @(negedge clk);param_we=0;param_wstrb=0;
        end
    endtask
    task verify_params(input integer l);
        integer j,p;
        reg [95:0] want;
        begin
            param_verify=1;
            for(j=0;j<outputs(l);j=j+1) begin
                p=base(l)+j;
                @(negedge clk);verify_addr=p;
                @(posedge clk);#2;want={pshift[p][31:0],pmult[p][31:0],pbias[p][31:0]};
                check(fc_param_rdata===want && param_broadcast===want,"Param read-back all 96 bits/fields");
            end
            @(negedge clk);param_verify=0;
        end
    endtask
    task reset_scoreboard;
        begin accepted=0;received=0;mismatches=0;changed=0;case_saturation=0;rq_min=127;rq_max=-127; end
    endtask
    task run_layer(input integer l,input integer change_field);
        integer j,bias,mult,shift,limit;
        begin
            layer=l;variant=change_field;case_name=$sformatf("FC%0d_variant%0d",l+1,change_field);
            reset_scoreboard();produced=0;producer_on=0;direct_mode=0;
            for(j=0;j<outputs(l);j=j+1) begin
                bias=blob_param(l,0,j);mult=blob_param(l,1,j);shift=blob_param(l,2,j);
                if(j==0) case(change_field) 1:bias=bias+1048576; 2:mult=mult/2; 3:shift=shift+1; endcase
                put_param(base(l)+j,bias,mult,shift);
            end
            verify_params(l);
            if(l==0) begin
                producer_on=1;
                while(!fifo_full) begin @(posedge clk);#2; end
            end else begin
                for(j=0;j<128;j=j+1) begin
                    @(negedge clk);hidden_we=1;hidden_wbank=(l==2);hidden_waddr=j;
                    hidden_wdata=(l==1) ? hidden0_golden[j]:hidden1_golden[j];
                    @(posedge clk);#2;
                end
                @(negedge clk);hidden_we=0;
                for(j=0;j<outputs(l)*16;j=j+1) begin
                    @(negedge clk);fcw_we=1;fcw_waddr=(l==2 ? 2048:0)+j;fcw_wdata=weight_word(l,j);
                    @(posedge clk);#2;
                end
                @(negedge clk);fcw_we=0;
            end
            @(negedge clk);mac_sel=l;mac_start=1;collect=1;
            @(posedge clk);#2;start_cycle=cycles;
            @(negedge clk);mac_start=0;
            limit=0;
            while(received<outputs(l) && limit<70000) begin @(posedge clk);#2;limit=limit+1; end
            check(received==outputs(l) && accepted==outputs(l),"layer result count/timeout");
            check(mismatches==0,"full requant comparison");
            if(l==0) check(produced==49152 && fifo_empty,"FC1 complete real FIFO stream");
            if(change_field==0) begin check(changed==0 && case_saturation==0,"baseline golden/saturation count");saturation=saturation+case_saturation; end
            else check(changed==1,"one Param element must change exactly one output");
            $display("PASS: R1-R3/R7 %s outputs=%0d mismatch=0 param_addr=%0d..%0d latency=4 rq_min=%0d rq_max=%0d saturations=%0d changed_outputs=%0d cycles_to_last_rq=%0d",
                case_name,received,base(l),base(l)+outputs(l)-1,rq_min,rq_max,case_saturation,changed,last_rq-start_cycle);
            if(change_field!=0) $display("OBS: R7 layer=%0d field=%0d out_idx=0 bias=%0d mult=%0d shift=%0d golden=%0d mutated=%0d other_outputs_unchanged=%0d",
                l+1,change_field,pbias[base(l)],pmult[base(l)],pshift[base(l)],golden_rq(l,0),expected[0],outputs(l)-1);
            repeat(6) begin @(posedge clk);#2;check(!rq_valid && !acc_valid && !mac_done,"no late pipeline outputs"); end
            collect=0;producer_on=0;cases=cases+1;
        end
    endtask
    task synthetic(input integer index,input integer x,input integer mult,input integer shift,input integer want,input string name);
        begin
            case_name=name;put_param(48+index,0,mult,shift);
            reset_scoreboard();direct_mode=1;collect=1;
            // Registered source convention, exactly as fc_mac drives valid.
            @(posedge clk);#2;direct_acc=x;direct_tag=index;direct_valid=1;source_cycle[index]=cycles;
            @(posedge clk);#2;direct_valid=0;
            repeat(3) begin @(posedge clk);#2; end
            check(received==1 && expected[0]==want && s8(rq)==want && mismatches==0,"synthetic boundary/rounding");
            $display("PASS: R5/R6 %s acc=%0d mult=%0d shift=%0d raw=%0d rq=%0d expected=%0d latency=4",
                name,x,mult,shift,rounded(x,0,mult,shift),s8(rq),want);
            repeat(2) begin @(posedge clk);#2;check(!rq_valid,"synthetic valid width"); end
            collect=0;cases=cases+1;
        end
    endtask
    initial begin
        fd=$fopen("preflight_ok.txt","r");check(fd!=0,"SHA-256 preflight guard missing");
        n=$fscanf(fd,"%h",guard);$fclose(fd);check(n==1 && guard==32'hF03A0001,"SHA-256 preflight guard invalid");
        fd=$fopen("blob.bin","rb");check(fd!=0,"blob open");n=$fread(blob,fd);$fclose(fd);check(n==422992,"blob byte count");
        $readmemh("encoder_flat_u64.hex",flat_golden);
        $readmemh("fc1_gelu_i8.hex",hidden0_golden);$readmemh("fc2_gelu_i8.hex",hidden1_golden);
        $readmemh("fc1_acc_i32.hex",gold1_acc);$readmemh("fc2_acc_i32.hex",gold2_acc);$readmemh("fc3_acc_i32.hex",gold3_acc);
        $readmemh("fc1_requant_i8.hex",gold1_rq);$readmemh("fc2_requant_i8.hex",gold2_rq);$readmemh("fc3_i8.hex",gold3_rq);
        repeat(2) @(posedge clk);@(negedge clk);rst_n=1;
        for(c=0;c<3;c=c+1) run_layer(c,0);
        $display("PASS: R1-R3 baseline_golden=280 mismatches=0 saturation_count=%0d Param_preverified=280 latency=4",saturation);
        for(c=0;c<3;c=c+1) for(k=1;k<=3;k=k+1) run_layer(c,k);
        synthetic(0,256,1,1,127,"positive_saturation");
        synthetic(1,-254,1,1,-127,"negative_saturation_not_minus128");
        synthetic(2,253,1,1,127,"exact_positive127");
        synthetic(3,-253,1,1,-127,"exact_negative127");
        synthetic(4,0,1,1,0,"zero");
        synthetic(5,3,1,1,2,"round_positive_half");
        synthetic(6,-3,1,1,-2,"round_negative_half");
        synthetic(7,2,1,1,1,"round_positive_even");
        synthetic(8,-2,1,1,-2,"round_negative_even_minus_half");
        synthetic(9,5,1,2,1,"round_positive_quarter");
        synthetic(10,-5,1,2,-2,"round_negative_quarter");
        synthetic(11,7,1,0,7,"zero_shift_positive");
        synthetic(12,-7,1,0,-7,"zero_shift_negative");
        synthetic(13,3,1,-1,6,"left_shift_positive");
        synthetic(14,-3,1,-1,-6,"left_shift_negative");
        $display("PASS: F-03a ALL cases=%0d outputs_compared=%0d checks=%0d cycles=%0d",cases,total_compared,checks,cycles);
        $finish;
    end
endmodule
