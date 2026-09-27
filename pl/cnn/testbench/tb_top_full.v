`timescale 1ns / 1ps

// T-07 full Top/real-M00 integration and D08 drain/reset fixture. Existing memory RTL/model unchanged.
module tb_top_full;
    reg clk = 0, resetn = 0;
    always #5 clk = ~clk;
    wire mem_rd_start, mem_rd_ready;
    wire [31:0] mem_rd_addr;
    wire [19:0] mem_rd_bytes;
    wire mem_rd_busy, mem_rd_valid, mem_rd_err;
    wire [63:0] mem_rd_data;
    wire mem_wr_start;
    wire [31:0] mem_wr_addr;
    wire [19:0] mem_wr_bytes;
    wire [63:0] mem_wr_data;
    wire mem_wr_busy, mem_wr_ready, mem_wr_err;
    wire M_AXI_AWID;
    wire [31:0] M_AXI_AWADDR;
    wire [7:0] M_AXI_AWLEN;
    wire [2:0] M_AXI_AWSIZE;
    wire [1:0] M_AXI_AWBURST;
    wire M_AXI_AWLOCK;
    wire [3:0] M_AXI_AWCACHE;
    wire [2:0] M_AXI_AWPROT;
    wire [3:0] M_AXI_AWQOS;
    wire M_AXI_AWVALID;
    wire M_AXI_AWREADY;
    wire [63:0] M_AXI_WDATA;
    wire [7:0] M_AXI_WSTRB;
    wire M_AXI_WLAST;
    wire M_AXI_WVALID;
    wire M_AXI_WREADY;
    wire M_AXI_BID;
    wire [1:0] M_AXI_BRESP;
    wire M_AXI_BVALID;
    wire M_AXI_BREADY;
    wire M_AXI_ARID;
    wire [31:0] M_AXI_ARADDR;
    wire [7:0] M_AXI_ARLEN;
    wire [2:0] M_AXI_ARSIZE;
    wire [1:0] M_AXI_ARBURST;
    wire M_AXI_ARLOCK;
    wire [3:0] M_AXI_ARCACHE;
    wire [2:0] M_AXI_ARPROT;
    wire [3:0] M_AXI_ARQOS;
    wire M_AXI_ARVALID;
    wire M_AXI_ARREADY;
    wire M_AXI_RID;
    wire [63:0] M_AXI_RDATA;
    wire [1:0] M_AXI_RRESP;
    wire M_AXI_RLAST;
    wire M_AXI_RVALID;
    wire M_AXI_RREADY;
    // R3-only test producer: normal Top never overlaps a read and pose write.
    // Exercise a REAL independent M00 write without forcing any RTL state.
    bit diagnostic_write=0, diagnostic_start=0;
    reg [31:0] diagnostic_addr=0;
    localparam [63:0] DIAGNOSTIC_WORD=64'h718293a4b5c6d7e8;
    pose_cnn_v1_0_M00_AXI dut (
        .M_AXI_ACLK(clk), .M_AXI_ARESETN(resetn),
        .mem_rd_start(mem_rd_start), .mem_rd_addr(mem_rd_addr), .mem_rd_bytes(mem_rd_bytes),
        .mem_rd_busy(mem_rd_busy), .mem_rd_data(mem_rd_data), .mem_rd_valid(mem_rd_valid),
        .mem_rd_ready(mem_rd_ready), .mem_rd_err(mem_rd_err),
        .mem_wr_start(diagnostic_write?diagnostic_start:mem_wr_start),
        .mem_wr_addr(diagnostic_write?diagnostic_addr:mem_wr_addr),
        .mem_wr_bytes(diagnostic_write?20'd24:mem_wr_bytes),
        .mem_wr_data(diagnostic_write?DIAGNOSTIC_WORD:mem_wr_data),
        .mem_wr_busy(mem_wr_busy), .mem_wr_ready(mem_wr_ready), .mem_wr_err(mem_wr_err),
        .M_AXI_AWID(M_AXI_AWID),
        .M_AXI_AWADDR(M_AXI_AWADDR),
        .M_AXI_AWLEN(M_AXI_AWLEN),
        .M_AXI_AWSIZE(M_AXI_AWSIZE),
        .M_AXI_AWBURST(M_AXI_AWBURST),
        .M_AXI_AWLOCK(M_AXI_AWLOCK),
        .M_AXI_AWCACHE(M_AXI_AWCACHE),
        .M_AXI_AWPROT(M_AXI_AWPROT),
        .M_AXI_AWQOS(M_AXI_AWQOS),
        .M_AXI_AWVALID(M_AXI_AWVALID),
        .M_AXI_AWREADY(M_AXI_AWREADY),
        .M_AXI_WDATA(M_AXI_WDATA),
        .M_AXI_WSTRB(M_AXI_WSTRB),
        .M_AXI_WLAST(M_AXI_WLAST),
        .M_AXI_WVALID(M_AXI_WVALID),
        .M_AXI_WREADY(M_AXI_WREADY),
        .M_AXI_BID(M_AXI_BID),
        .M_AXI_BRESP(M_AXI_BRESP),
        .M_AXI_BVALID(M_AXI_BVALID),
        .M_AXI_BREADY(M_AXI_BREADY),
        .M_AXI_ARID(M_AXI_ARID),
        .M_AXI_ARADDR(M_AXI_ARADDR),
        .M_AXI_ARLEN(M_AXI_ARLEN),
        .M_AXI_ARSIZE(M_AXI_ARSIZE),
        .M_AXI_ARBURST(M_AXI_ARBURST),
        .M_AXI_ARLOCK(M_AXI_ARLOCK),
        .M_AXI_ARCACHE(M_AXI_ARCACHE),
        .M_AXI_ARPROT(M_AXI_ARPROT),
        .M_AXI_ARQOS(M_AXI_ARQOS),
        .M_AXI_ARVALID(M_AXI_ARVALID),
        .M_AXI_ARREADY(M_AXI_ARREADY),
        .M_AXI_RID(M_AXI_RID),
        .M_AXI_RDATA(M_AXI_RDATA),
        .M_AXI_RRESP(M_AXI_RRESP),
        .M_AXI_RLAST(M_AXI_RLAST),
        .M_AXI_RVALID(M_AXI_RVALID),
        .M_AXI_RREADY(M_AXI_RREADY)
    );
    axi4_slave_mem_model memory (
        .clk(clk), .resetn(resetn),
        .M_AXI_AWID(M_AXI_AWID),
        .M_AXI_AWADDR(M_AXI_AWADDR),
        .M_AXI_AWLEN(M_AXI_AWLEN),
        .M_AXI_AWSIZE(M_AXI_AWSIZE),
        .M_AXI_AWBURST(M_AXI_AWBURST),
        .M_AXI_AWLOCK(M_AXI_AWLOCK),
        .M_AXI_AWCACHE(M_AXI_AWCACHE),
        .M_AXI_AWPROT(M_AXI_AWPROT),
        .M_AXI_AWQOS(M_AXI_AWQOS),
        .M_AXI_AWVALID(M_AXI_AWVALID),
        .M_AXI_AWREADY(M_AXI_AWREADY),
        .M_AXI_WDATA(M_AXI_WDATA),
        .M_AXI_WSTRB(M_AXI_WSTRB),
        .M_AXI_WLAST(M_AXI_WLAST),
        .M_AXI_WVALID(M_AXI_WVALID),
        .M_AXI_WREADY(M_AXI_WREADY),
        .M_AXI_BID(M_AXI_BID),
        .M_AXI_BRESP(M_AXI_BRESP),
        .M_AXI_BVALID(M_AXI_BVALID),
        .M_AXI_BREADY(M_AXI_BREADY),
        .M_AXI_ARID(M_AXI_ARID),
        .M_AXI_ARADDR(M_AXI_ARADDR),
        .M_AXI_ARLEN(M_AXI_ARLEN),
        .M_AXI_ARSIZE(M_AXI_ARSIZE),
        .M_AXI_ARBURST(M_AXI_ARBURST),
        .M_AXI_ARLOCK(M_AXI_ARLOCK),
        .M_AXI_ARCACHE(M_AXI_ARCACHE),
        .M_AXI_ARPROT(M_AXI_ARPROT),
        .M_AXI_ARQOS(M_AXI_ARQOS),
        .M_AXI_ARVALID(M_AXI_ARVALID),
        .M_AXI_ARREADY(M_AXI_ARREADY),
        .M_AXI_RID(M_AXI_RID),
        .M_AXI_RDATA(M_AXI_RDATA),
        .M_AXI_RRESP(M_AXI_RRESP),
        .M_AXI_RLAST(M_AXI_RLAST),
        .M_AXI_RVALID(M_AXI_RVALID),
        .M_AXI_RREADY(M_AXI_RREADY)
    );


    reg  reg_start = 0;
    reg  reg_clear_status = 0;
    reg [31:0] reg_cmd = 0;
    reg [31:0] reg_input_addr = 0;
    reg [31:0] reg_weight_addr = 0;
    reg [31:0] reg_output_addr = 0;
    wire  status_busy;
    wire  status_done;
    wire [3:0] status_error;
    reg  cfg_ok = 0;
    wire  loader_start;
    wire  loader_done;
    wire  loader_err;
    wire [63:0] ld_data;
    wire  ld_valid;
    wire  ld_ready;
    wire  enc_start;
    wire  enc_done;
    wire  in_we;
    wire [10:0] in_waddr;
    wire [63:0] in_wdata;
    wire  fc_start;
    wire  fc_done;
    wire [1:0] fc_sel;
    wire  fifo_we;
    wire [63:0] fifo_wdata;
    wire  fifo_full;
    wire [191:0] pose_data;

    wire param_sel_fc, lut_sel_fc;
    pose_cnn_ctrl ctrl (
        .param_sel_fc(param_sel_fc), .lut_sel_fc(lut_sel_fc),
        .clk(clk),
        .rst_n(resetn),
        .reg_start(reg_start),
        .reg_clear_status(reg_clear_status),
        .reg_cmd(reg_cmd),
        .reg_input_addr(reg_input_addr),
        .reg_weight_addr(reg_weight_addr),
        .reg_output_addr(reg_output_addr),
        .status_busy(status_busy),
        .status_done(status_done),
        .status_error(status_error),
        .cfg_ok(cfg_ok),
        .mem_rd_start(mem_rd_start),
        .mem_rd_addr(mem_rd_addr),
        .mem_rd_bytes(mem_rd_bytes),
        .mem_rd_busy(mem_rd_busy),
        .mem_rd_data(mem_rd_data),
        .mem_rd_valid(mem_rd_valid),
        .mem_rd_ready(mem_rd_ready),
        .mem_rd_err(mem_rd_err),
        .mem_wr_start(mem_wr_start),
        .mem_wr_addr(mem_wr_addr),
        .mem_wr_bytes(mem_wr_bytes),
        .mem_wr_busy(mem_wr_busy),
        .mem_wr_data(mem_wr_data),
        .mem_wr_ready(mem_wr_ready),
        .mem_wr_err(mem_wr_err),
        .loader_start(loader_start),
        .loader_done(loader_done),
        .loader_err(loader_err),
        .ld_data(ld_data),
        .ld_valid(ld_valid),
        .ld_ready(ld_ready),
        .enc_start(enc_start),
        .enc_done(enc_done),
        .in_we(in_we),
        .in_waddr(in_waddr),
        .in_wdata(in_wdata),
        .fc_start(fc_start),
        .fc_done(fc_done),
        .fc_sel(fc_sel),
        .fifo_we(fifo_we),
        .fifo_wdata(fifo_wdata),
        .fifo_full(fifo_full),
        .pose_data(pose_data)
    );

    loader_stub loader(.clk(clk),.resetn(resetn),.loader_start(loader_start),
        .ld_data(ld_data),.ld_valid(ld_valid),.ld_ready(ld_ready),.loader_done(loader_done),.loader_err(loader_err));
    in_ram_stub input_ram(.clk(clk),.resetn(resetn),.in_we(in_we),.in_waddr(in_waddr),.in_wdata(in_wdata));
    enc_stub encoder(.clk(clk),.resetn(resetn),.enc_start(enc_start),.enc_done(enc_done));
    wire [1:0] tested_sel=fc_start?fc_sel:(fc_sel^2'b11);
    fc_stub fc(.clk(clk),.resetn(resetn),.fc_start(fc_start),.fc_sel(tested_sel),
        .fifo_we(fifo_we),.fifo_wdata(fifo_wdata),.fifo_full(fifo_full),.fc_done(fc_done),.pose_data(pose_data),
        .fc_param_raddr(),.fc_param_rdata(96'd0),.fc_lut_raddr(),.fc_lut_rdata(8'd0),
        .fcw_raddr(),.fcw_rdata(64'd0),.flat_raddr(),.flat_rdata(64'd0));

    // L-07 S3: real Loader read-port fixture, separate from the existing
    // protocol-only loader_stub. Preload via public LOAD ports once; no RAM
    // forces/backdoors. This is not the X-02 whole-core LOAD integration.
    // Unmodified Encoder/FC stubs have no RAM address ports. These TB-local
    // address producers model Encoder's nonzero residual addresses and FC's
    // independent requests. The production Loader performs the actual mux.
    reg probe_resetn=0,probe_start=0,probe_valid=0;
    reg [63:0] probe_data=0;
    wire probe_done,probe_err,probe_ready,probe_cfg;
    wire [31:0] probe_mult,probe_shift,probe_scale;
    wire [127:0] probe_conv;
    wire [63:0] probe_fcw;
    wire [95:0] probe_enc_param_data,probe_fc_param_data;
    wire [7:0] probe_enc_lut_data,probe_fc_lut_data;
    wire [8:0] probe_enc_param_addr=9'd17;
    wire [9:0] probe_enc_lut_addr=10'd73;
    reg [8:0] probe_fc_param_addr=9'd48;
    reg [9:0] probe_fc_lut_addr=10'd612;
    bit probe_loaded=0;
    integer probe_pfirst[0:4],probe_pcount[0:4],probe_pbase[0:4];
    integer probe_requests=0,probe_enc_reads=0,probe_fc_reads=0;
    integer probe_enter=0,probe_exit=0,probe_handoffs=0;
    weight_param_loader read_port_loader (
        .clk(clk),.rst_n(probe_resetn),.loader_start(probe_start),
        .loader_done(probe_done),.loader_err(probe_err),
        .ld_data(probe_data),.ld_valid(probe_valid),.ld_ready(probe_ready),.cfg_ok(probe_cfg),
        .pool_mult(probe_mult),.pool_shift(probe_shift),.output_scale_bits(probe_scale),
        .param_sel_fc(param_sel_fc),.lut_sel_fc(lut_sel_fc),
        .conv_raddr(9'd0),.conv_rdata(probe_conv),.fcw_raddr(12'd0),.fcw_rdata(probe_fcw),
        .enc_param_raddr(probe_enc_param_addr),.enc_param_rdata(probe_enc_param_data),
        .fc_param_raddr(probe_fc_param_addr),.fc_param_rdata(probe_fc_param_data),
        .enc_lut_raddr(probe_enc_lut_addr),.enc_lut_rdata(probe_enc_lut_data),
        .fc_lut_raddr(probe_fc_lut_addr),.fc_lut_rdata(probe_fc_lut_data)
    );
    function automatic [31:0] probe_field(input integer a,input integer f);
        case(f)
            0:probe_field=32'h76540000+32'(a);
            1:probe_field=32'h12340000+32'(a*3);
            default:probe_field=32'd31;
        endcase
    endfunction
    function automatic [95:0] probe_param(input integer a);
        probe_param={probe_field(a,2),probe_field(a,1),probe_field(a,0)};
    endfunction
    function automatic [7:0] probe_lut(input integer a);
        probe_lut=8'(a);
    endfunction
    function automatic [63:0] probe_word(input integer b);
        reg [63:0] v;
        integer k,a;
        begin
            v=0;
            for(integer l=0;l<5;l=l+1) for(integer f=0;f<3;f=f+1) begin
                k=b-probe_pfirst[l]-f*(probe_pcount[l]/2);
                if(k>=0 && k<probe_pcount[l]/2) begin
                    a=probe_pbase[l]+2*k;v={probe_field(a+1,f),probe_field(a,f)};
                end
            end
            if(b>=3594) for(k=0;k<8;k=k+1) v[k*8+:8]=probe_lut((b-3594)*8+k);
            case(b)
                0:v={32'd2,32'h36574c50};
                1:v={32'h3cb76adb,32'd105748};
                2:v={32'h783b66b4,32'h3bd997a8};
                3:v={32'd0,32'd31};
                default:begin end
            endcase
            probe_word=v;
        end
    endfunction
    task preload_read_fixture;
        integer elapsed;
        begin
            probe_pfirst[0]=94;probe_pcount[0]=16;probe_pbase[0]=0;
            probe_pfirst[1]=694;probe_pcount[1]=32;probe_pbase[1]=16;
            probe_pfirst[2]=742;probe_pcount[2]=128;probe_pbase[2]=48;
            probe_pfirst[3]=2982;probe_pcount[3]=128;probe_pbase[3]=176;
            probe_pfirst[4]=3558;probe_pcount[4]=24;probe_pbase[4]=304;
            repeat(2) @(negedge clk);
            probe_resetn=1;probe_start=1;
            @(negedge clk);probe_start=0;elapsed=0;
            for(integer b=0;b<3722;b=b+1) begin
                probe_data=probe_word(b);probe_valid=1;
                @(posedge clk);
                while(!probe_ready) begin @(posedge clk);end
                @(negedge clk);probe_valid=0;
            end
            while(!probe_done) begin
                @(negedge clk);elapsed=elapsed+1;check(elapsed<20,"S3 fixture LOAD completion bound");
            end
            check(probe_cfg && !probe_err,"S3 real Loader accepts deterministic fixture");
            probe_loaded=1;
            $display("PASS: L-07 S3 fixture public_LOAD_beats=3722 cfg=1 err=0 hierarchy_RAM_access=0");
        end
    endtask
    always @(negedge clk) begin : read_address_producers
        reg [207:0] held;
        if(probe_loaded && resetn) begin
            held={probe_enc_param_data,probe_fc_param_data,probe_enc_lut_data,probe_fc_lut_data};
            if(ctrl.state_reg>=7 && ctrl.state_reg<=9) begin
                probe_fc_param_addr=9'(48+128*(int'(ctrl.state_reg)-7)+probe_requests%24);
                probe_fc_lut_addr=10'((ctrl.state_reg==7?512:768)+100+probe_requests%24);
            end
            #2;
            check({probe_enc_param_data,probe_fc_param_data,probe_enc_lut_data,probe_fc_lut_data}===held,
                "S3 real Loader read data holds when FC address changes between edges");
        end
    end
    always @(posedge clk) begin : shared_read_monitor
        reg [3:0] sampled_state;
        reg [95:0] want_param;
        reg [7:0] want_lut;
        bit sampled_enc_done,sampled_fc_done,sampled_fc_start,sampled_seen;
        reg [1:0] sampled_fc_sel;
        if(probe_loaded && resetn) begin
            sampled_state=ctrl.state_reg;
            sampled_enc_done=enc_done;sampled_fc_done=fc_done;sampled_seen=ctrl.fc_done_seen_reg;
            sampled_fc_start=fc_start;sampled_fc_sel=fc_sel;
            check(param_sel_fc===(sampled_state>=7 && sampled_state<=9) && lut_sel_fc===param_sel_fc,
                "S3 current state drives both real Loader selectors");
            want_param=probe_param(param_sel_fc?probe_fc_param_addr:probe_enc_param_addr);
            want_lut=probe_lut(lut_sel_fc?probe_fc_lut_addr:probe_enc_lut_addr);
            if(sampled_state==6) probe_enc_reads=probe_enc_reads+1;
            if(param_sel_fc) begin
                check(probe_enc_param_addr==17 && probe_enc_lut_addr==73 &&
                    want_param!==probe_param(17) && want_lut!==probe_lut(73),
                    "S3 nonzero stale Encoder addresses produce different data and remain driven");
                probe_fc_reads=probe_fc_reads+1;
            end
            probe_requests=probe_requests+1;
            #2;
            check(probe_enc_param_data===want_param && probe_fc_param_data===want_param &&
                probe_enc_lut_data===want_lut && probe_fc_lut_data===want_lut,
                "S3 both outputs equal golden for pre-edge address/select, including transition edges");
            check(param_sel_fc===(ctrl.state_reg>=7 && ctrl.state_reg<=9) && lut_sel_fc===param_sel_fc,
                "S3 select follows state change without an extra register");
            if(sampled_state==6 && ctrl.state_reg==7) begin
                check(sampled_enc_done && sampled_fc_start && sampled_fc_sel==0 &&
                    param_sel_fc && want_param===probe_param(17),
                    "S3 ENC-to-FC1: start samples while ENC-selected, FC reads begin next edge");
                probe_enter=probe_enter+1;
            end
            if((sampled_state==7 && ctrl.state_reg==8) || (sampled_state==8 && ctrl.state_reg==9)) begin
                check((sampled_fc_done || sampled_seen) && sampled_fc_start && param_sel_fc,
                    "S3 FC1/2 handoff requires done/seen, keeps FC read ownership");
                probe_handoffs=probe_handoffs+1;
            end
            if(sampled_state==9 && ctrl.state_reg==10) begin
                check((sampled_fc_done || sampled_seen) && !param_sel_fc && !lut_sel_fc,
                    "S3 FC3-to-WR releases read ownership at completed transition");
                probe_exit=probe_exit+1;
            end
        end
    end

    localparam integer LAST_CASE=12;
    localparam [31:0] LOAD_BASE=32'h1c000050, INPUT_BASE=32'h1d000000;
    localparam [31:0] S1=32'haaaa0001,S2=32'hcccc0003,SW=32'hfc1a0010,SI=32'h24681357;
    localparam [63:0] UNWRITTEN=64'hdeadbeefbad00001;
    integer selected=-1,case_id,leg,cycle=0,phase=0,tests=0,cases_done=0,events;
    integer began,finished,commands,ar1,ar2,r1,r2,in_words,fc_words,enc_starts,fc_starts;
    integer wr_starts,aw_count,w_count,b_count,ready_count,ready_run,max_ready_run;
    integer write_edge,last_w,last_b,write_end,full_cycles,drain_cycles,inject_before,fc_before;
    integer fc_edges[0:2],done_edges[0:2],fc_cycles[0:2],fc_done_baseline[0:2];
    integer ar_left,ar_beats,fault=0,error_pushes=-1;
    reg [31:0] expected_ar,output_base;
    reg [191:0] expected_pose,pose_before_edge;
    reg [63:0] observed_word;
    reg [3:0] previous_state;
    bit active=0,previous_rd=0,previous_wr=0,previous_start=0,previous_fc=0,previous_write=0;
    bit injected=0,restart_probe=0;
    string case_name;


    // BASELINE_T06 is only for replay against the saved pre-T07 controller.
    // Default execution always requires the real ERR_DRAIN state.
    bit legacy_drain=0;
    integer drain_entries=0, drain_residence=0, drain_discarded=0, read_fall=0;
    integer drain_from=-1, both_busy_cycles=0, write_only_cycles=0;
    reg [3:0] drain_prior_state=0;
    initial legacy_drain=$test$plusargs("BASELINE_T06");
    task reset_drain_observation;
        begin
            drain_entries=0;drain_residence=0;drain_discarded=0;read_fall=0;
            drain_from=-1;both_busy_cycles=0;write_only_cycles=0;drain_prior_state=0;
        end
    endtask
    task observe_drain;
        begin
            if(ctrl.mem_rd_busy_prev_reg && !mem_rd_busy) read_fall=cycle;
            if(mem_rd_err && (ctrl.state_reg==2 || ctrl.state_reg==3 || ctrl.state_reg==5 || ctrl.state_reg==7)) begin
                check(!ld_valid && !in_we && !fifo_we && mem_rd_ready,
                    "R1 immediate error-cycle consumer gating and RREADY=1");
                check(ctrl.run_error_next==4,"R1 latch MEM_RD_ERR before drain entry");
                if(!legacy_drain) check(ctrl.state_next==11,"R1 each read origin selects ERR_DRAIN=1011");
                drain_from=ctrl.state_reg;
            end
            if(mem_rd_err && mem_rd_valid && mem_rd_ready) drain_discarded=drain_discarded+1;
            if(ctrl.state_reg==11) begin
                if(drain_prior_state!=11) drain_entries=drain_entries+1;
                drain_residence=drain_residence+1;
                check(status_busy && !status_done && status_error==0 && ctrl.run_error_reg==4 &&
                    ctrl.run_error_next==4,"R2 internal error retained; STATUS waits for FINISH");
                check(mem_rd_ready && {ld_valid,in_we,fifo_we,ld_data,in_wdata,fifo_wdata,
                    mem_rd_start,mem_wr_start,loader_start,enc_start,fc_start}==='0,
                    "R2 drain accepts/discards; every consumer and START/data output is zero");
                check(ctrl.state_next==((!mem_rd_busy&&!mem_wr_busy)?12:11),
                    "R3 FINISH requires BOTH engines idle");
                if(mem_rd_busy && mem_wr_busy) both_busy_cycles=both_busy_cycles+1;
                if(!mem_rd_busy && mem_wr_busy) write_only_cycles=write_only_cycles+1;
            end
            drain_prior_state=ctrl.state_reg;
        end
    endtask

    function automatic [63:0] pattern(input reg [31:0] addr,seed);
        pattern={seed^32'ha5c39e71,addr^seed};
    endfunction
    function automatic [191:0] pose_pattern(input integer tag);
        reg [191:0] result;
        begin
            result=0;
            for(integer j=0;j<24;j=j+1) result[8*j+:8]=(tag*31+j*7)&255;
            pose_pattern=result;
        end
    endfunction
    task automatic check(input bit ok,input string message);
        if(!ok) begin
            $display("FAIL: T-06 %s case=%0d leg=%0d cycle=%0d state=%0d %s",case_name,case_id,leg,cycle,ctrl.state_reg,message);
            $fatal(1,"T-06 full path mismatch");
        end
    endtask
    always @(negedge clk) begin
        if(active && phase==2 && !injected) begin
            if((fault==4 || fault==5) && commands==1 && ar1==1) begin
                memory.inject_rlast_mode=fault-3;injected=1;
            end
            if((fault==1 && commands==1 && ar1==1) || (fault==2 && commands==2 && ar2==80)) begin
                memory.inject_rresp=2'b10;memory.inject_rresp_beat=4;injected=1;
            end
        end
    end
    always @(posedge clk) begin
        cycle=cycle+1;pose_before_edge=pose_data;
        if(resetn && active) begin
            observe_drain;
            if(fault==0 || fault==3) check(ctrl.state_reg!=11,"normal/write-error paths never enter ERR_DRAIN");
            if(ctrl.state_reg==11) drain_cycles=drain_cycles+1;
            if(reg_start && ctrl.state_reg==0) began=cycle;
            check(!(previous_start && mem_rd_start) && !(previous_fc && fc_start) &&
                  !(previous_write && mem_wr_start),"read/FC/write STARTs are one-cycle pulses");
            previous_start=mem_rd_start;previous_fc=fc_start;previous_write=mem_wr_start;
            if(mem_rd_start) begin
                check(!mem_rd_busy && commands<2,"read START while idle, two commands maximum");
                if(phase==1) begin
                    check(mem_rd_addr==LOAD_BASE+(commands==0?0:399152) &&
                          mem_rd_bytes==(commands==0?5936:23840),"resident LOAD addresses and lengths");
                end else if(commands==0) begin
                    check(ctrl.state_reg==1 && mem_rd_addr==INPUT_BASE && mem_rd_bytes==11520,"input snapshot read");
                end else begin
                    check(ctrl.state_reg==6 && fc_start && fc_sel==0 &&
                          mem_rd_addr==LOAD_BASE+5936 && mem_rd_bytes==393216,"FC1 saved-base read and simultaneous START");
                end
                expected_ar=mem_rd_addr;ar_left=mem_rd_bytes;commands=commands+1;
            end
            if(M_AXI_ARVALID && M_AXI_ARREADY) begin
                ar_beats=ar_left/8;if(ar_beats>16) ar_beats=16;
                if(ar_beats>(4096-expected_ar%4096)/8) ar_beats=(4096-expected_ar%4096)/8;
                check(ar_left>0 && M_AXI_ARADDR==expected_ar && int'(M_AXI_ARLEN)+1==ar_beats,"complete continuous AR ranges");
                ar_left=ar_left-8*ar_beats;expected_ar=expected_ar+8*ar_beats;
                if(commands==1) ar1=ar1+1;else ar2=ar2+1;
            end
            if(M_AXI_RVALID && M_AXI_RREADY) begin
                if(commands==1) r1=r1+1;else r2=r2+1;
            end
            if(in_we) begin
                check(phase==2 && int'(in_waddr)==in_words && in_words<1440 &&
                      in_wdata===pattern(INPUT_BASE+8*in_words,SI),"all input words/address order");
                in_words=in_words+1;
            end
            if(enc_start) begin
                enc_starts=enc_starts+1;
                check(in_words==1440 && !mem_rd_busy && previous_rd,"Encoder follows completed input read");
            end
            if(fc_start) begin
                check(phase==2 && fc_starts<3 && int'(fc_sel)==fc_starts,"FC START selection order 0,1,2");
                if(!restart_probe) check(!fc.active && fc.count==0,"every normal FC START is idle-only");
                fc_edges[fc_starts]=cycle;fc_starts=fc_starts+1;
            end
            if(ctrl.state_reg>=7 && ctrl.state_reg<=9) begin
                fc_cycles[ctrl.state_reg-7]=fc_cycles[ctrl.state_reg-7]+1;
                if(fc_done && done_edges[ctrl.state_reg-7]==0) done_edges[ctrl.state_reg-7]=cycle;
                check(status_busy,"FC stages stay busy");
            end
            if(ctrl.state_reg==7) begin
                if(mem_rd_err || ctrl.run_error_reg==4) begin
                    if(error_pushes<0) error_pushes=fc_words;
                    check(!fifo_we && mem_rd_ready && !fc_start,"FC1 error stops pushes and drains with READY");
                    drain_cycles=drain_cycles+1;
                end else begin
                    check(fifo_we===(mem_rd_valid&&!fifo_full) && mem_rd_ready===!fifo_full &&
                          fifo_wdata===mem_rd_data,"FC1 stream equations");
                    if(fifo_full) begin full_cycles=full_cycles+1;check(!M_AXI_RREADY,"full stalls actual AXI");end
                end
            end
            if(fifo_we) begin
                check(!fifo_full && fc_words<49152 && fifo_wdata===pattern(LOAD_BASE+5936+8*fc_words,SW),
                    "all 49152 FC1 push words, no LOAD-region contamination");
                fc_words=fc_words+1;
            end
            if(ctrl.state_reg==8 || ctrl.state_reg==9) begin
                check({mem_rd_start,mem_rd_ready,loader_start,ld_valid,enc_start,in_we,fifo_we}==='0,
                    "FC2/FC3 have no read/input/FIFO activity");
            end
            if(mem_wr_start) begin
                check(phase==2 && ctrl.state_reg==9 && !mem_wr_busy && wr_starts==0 &&
                      mem_wr_addr==output_base && mem_wr_bytes==24,"one pose write from FC3, snapshot address/24 bytes");
                check(output_base[4:0]==0 && (output_base%4096)+24<=4096,"32-byte aligned pose cannot cross 4KiB");
                check(pose_data===expected_pose,"pose valid at write START");
                wr_starts=wr_starts+1;write_edge=cycle;
            end
            if(ctrl.state_reg==10) begin
                check(status_busy && int'(ctrl.beat_reg)==w_count && ctrl.beat_reg<=3,"WR beat exactly follows accepted W, bounded 0..3");
                check(mem_wr_data===expected_pose[(ctrl.beat_reg<3?ctrl.beat_reg:2)*64+:64],"correct pose slice and valid final data during B wait");
                if(mem_wr_ready) check(ctrl.state_next==10,"accepted beat precedes completion test");
                else if(previous_wr && !mem_wr_busy) begin
                    write_end=cycle;
                    check(b_count==1 && ctrl.state_next==12 && ctrl.run_error_next==(mem_wr_err?5:0),
                        "WR goes directly to FINISH after final B/busy falling, with error priority");
                end else check(ctrl.state_next==10,"WR waits for true busy falling, never initial idle");
            end
            check(mem_wr_ready===(M_AXI_WVALID&&M_AXI_WREADY),"each producer advance is one AXI W acceptance");
            if(mem_wr_ready) begin
                ready_count=ready_count+1;ready_run=ready_run+1;
                if(ready_run>max_ready_run) max_ready_run=ready_run;
            end else ready_run=0;
            if(M_AXI_AWVALID && M_AXI_AWREADY) begin
                check(aw_count==0 && M_AXI_AWADDR==output_base && M_AXI_AWLEN==2 &&
                      M_AXI_AWSIZE==3 && M_AXI_AWBURST==1,"one three-beat AW, exact pose range");
                aw_count=aw_count+1;
            end
            if(M_AXI_WVALID && M_AXI_WREADY) begin
                check(w_count<3 && M_AXI_WDATA===expected_pose[w_count*64+:64] &&
                      M_AXI_WSTRB==8'hff && M_AXI_WLAST==(w_count==2),"all W slices, strobe and last exact");
                w_count=w_count+1;last_w=cycle;
            end
            if(M_AXI_BVALID && M_AXI_BREADY) begin
                check(mem_wr_busy,"write busy remains high through final B acceptance");
                b_count=b_count+1;last_b=cycle;
            end
            if(previous_state!=ctrl.state_reg || mem_rd_start || fc_start || mem_wr_start || mem_wr_ready ||
               (previous_wr&&!mem_wr_busy))
                $fdisplay(events,"%0d,%0d,%0d,%0d,%0d,%b,%b,%b,%b,%0d,%b,%0d,%0d,%0d",
                    case_id,leg,phase,cycle,ctrl.state_reg,mem_rd_busy,mem_wr_busy,fc_start,fc_done,fc_sel,
                    mem_wr_ready,ctrl.beat_reg,fc_words,w_count);
            previous_state=ctrl.state_reg;previous_rd=mem_rd_busy;previous_wr=mem_wr_busy;
            #1;
            if(began!=0 && !status_busy && finished==0) finished=cycle;
        end else #1;
        if(resetn && pose_data!==pose_before_edge)
            check(fc_done && fc.selected_reg==2 && pose_data===fc.pose_value,"pose changes only at FC3 completion, otherwise holds across runs");
    end
    task clear_observation;
        begin
            reset_drain_observation;
            probe_enc_reads=0;probe_fc_reads=0;probe_enter=0;probe_exit=0;probe_handoffs=0;
            began=0;finished=0;commands=0;ar1=0;ar2=0;r1=0;r2=0;in_words=0;fc_words=0;enc_starts=0;fc_starts=0;
            wr_starts=0;aw_count=0;w_count=0;b_count=0;ready_count=0;ready_run=0;max_ready_run=0;
            write_edge=0;last_w=0;last_b=0;write_end=0;full_cycles=0;drain_cycles=0;error_pushes=-1;
            previous_rd=0;previous_wr=0;previous_start=0;previous_fc=0;previous_write=0;previous_state=0;injected=0;
            inject_before=memory.injection_count;fc_before=fc.accepted_starts;
            for(integer j=0;j<3;j=j+1) begin fc_edges[j]=0;done_edges[j]=0;fc_cycles[j]=0;fc_done_baseline[j]=fc.phase_dones[j];end
        end
    endtask
    task wait_finish;
        begin
            @(posedge clk);#2;check(status_busy && !status_done && status_error==0,"START clears display");
            @(negedge clk);reg_start=0;reg_cmd=32'hdeadbeef;reg_input_addr=32'h20000000;
            reg_output_addr=32'h2f000000;reg_weight_addr=32'h2e000000;
            while(status_busy) begin @(posedge clk);#2;check(cycle-began<2000000,"bounded full command");end
            check(!mem_rd_busy && !mem_wr_busy,"Top finishes only after memory idle");
            repeat(3) begin @(posedge clk);#2;end
            @(negedge clk);active=0;memory.check_quiescent;
            check(memory.violation_count==0 && loader.violations==0 && input_ram.violations==0 && fc.violations==0,
                "zero unexpected AXI/C12/consumer violations");
        end
    endtask
    task do_load;
        begin
            @(negedge clk);clear_observation;phase=1;cfg_ok=0;reg_cmd=1;reg_weight_addr=LOAD_BASE;reg_start=1;active=1;
            wait_finish;
            check(status_done && status_error==0 && commands==2 && r1==742 && r2==2980 && loader.received_count==3722,
                "LOAD resident words complete");
            check(ctrl.load_base_reg==LOAD_BASE && ctrl.ld2_addr_reg==LOAD_BASE+399152 &&
                  ctrl.fc1_addr_reg==LOAD_BASE+5936,"new LOAD base and both precomputed addresses agree");
            for(integer j=0;j<3722;j=j+1)
                check(loader.received[j]===(j<742?pattern(LOAD_BASE+8*j,S1):pattern(LOAD_BASE+399152+8*(j-742),S2)),"all Loader words");
            cfg_ok=1;
            $display("PASS: T-06 LOAD case=%0d leg=%0d cycles=%0d AR=%0d+%0d words=3722",case_id,leg,finished-began,ar1,ar2);
        end
    endtask
    task start_infer;
        begin
            @(negedge clk);clear_observation;phase=2;input_ram.begin_transfer;
            output_base=32'h1e000000+case_id*8192+leg*64;
            if(case_id==4) output_base=32'h1e01ffe0;
            expected_pose=pose_pattern(case_id*4+leg+1);fc.pose_value=expected_pose;
            for(integer j=-1;j<4;j=j+1) check(memory.mem_word(output_base+j*8)===UNWRITTEN,"target and adjacent guard words initially unwritten");
            if(fault==3) memory.inject_bresp=2'b10;
            reg_cmd=0;reg_input_addr=INPUT_BASE;reg_weight_addr=32'h1c100050;reg_output_addr=output_base;
            reg_start=1;active=1;
        end
    endtask
    task do_infer;
        integer want_error;
        begin
            start_infer;wait_finish;tests=tests+1;
            want_error=fault==0?0:(fault==3?5:4);
            check(status_done==(want_error==0) && status_error==want_error,"final sticky result");
            check(ar1==90 && r1==1440 && input_ram.write_count==in_words,"complete input read");
            check(memory.injection_count-inject_before==(fault==0?0:1),"one requested error injection");
            for(integer j=0;j<in_words;j=j+1) check(input_ram.mem[j]===pattern(INPUT_BASE+8*j,SI),"full RAM image comparison");
            for(integer j=0;j<fc.push_count;j=j+1) check(fc.pushed[j]===pattern(LOAD_BASE+5936+8*j,SW),"full FIFO push sequence");
            for(integer j=0;j<fc.pop_count;j=j+1) check(fc.consumed[j]===pattern(LOAD_BASE+5936+8*j,SW),"full FIFO pop sequence");
            if(fault==1) begin
                check(commands==1 && in_words==21 && enc_starts==0 && fc_starts==0 && wr_starts==0,"input error precedes all compute starts");
            end else begin
                check(commands==2 && ar2==3072 && r2==49152 && in_words==1440 && enc_starts==1,"full input and FC read ranges");
                if(fault==2) begin
                    check(fc_words==error_pushes && fc_words<49152 && fc.active && fc_starts==1 && wr_starts==0 &&
                          drain_cycles>0 && full_cycles>0,"FC error drains DDR but does not abort unfinished FC");
                end else begin
                    check(fc_starts==3 && fc.accepted_starts==fc_before+3 && fc_words==49152 && fc.pop_count==49152 &&
                          !fc.active && fc.count==0 && fc.selected_reg==2 && fc.sel_changed_cycles>0,"three idle-only latched FC stages completed");
                    for(integer j=0;j<3;j=j+1) check(fc.phase_dones[j]==fc_done_baseline[j]+1 && done_edges[j]>fc_edges[j],"one completion per stage");
                    check(fc.phase_done_cycle[1]-fc.phase_start_cycle[1]==(fc.fc2_delay_cycles==0?1:fc.fc2_delay_cycles) &&
                          fc.phase_done_cycle[2]-fc.phase_start_cycle[2]==(fc.fc3_delay_cycles==0?1:fc.fc3_delay_cycles),"FC2/3 configured completion delays");
                    check(wr_starts==1 && aw_count==1 && w_count==3 && ready_count==3 && b_count==1 && write_end>last_b &&
                          pose_data===expected_pose,"one 24B write; all three ready samples and final B observed");
                    for(integer j=0;j<24;j=j+1) begin
                        observed_word=memory.mem_word(output_base+(j/8)*8);
                        check(observed_word[(j%8)*8+:8]===expected_pose[j*8+:8],"all 24 stored pose bytes match");
                    end
                end
            end
            check(memory.mem_word(output_base-8)===UNWRITTEN && memory.mem_word(output_base+24)===UNWRITTEN,"both unwritten pose guard words preserved");
            if(fault==0 || fault==3) begin
                check(probe_enc_reads>0 && probe_fc_reads>0 && probe_enter==1 && probe_exit==1 && probe_handoffs==2,
                    "S3 normal INFER exercises all ownership transitions and stale-address exclusion");
                $display("PASS: L-07 S3 case=%0d leg=%0d ENC_reads=%0d FC_reads=%0d stale_enc_param=17 stale_enc_lut=73 entry=%0d FC_handoffs=%0d exit=%0d mismatches=0 read_latency=1",
                    case_id,leg,probe_enc_reads,probe_fc_reads,probe_enter,probe_handoffs,probe_exit);
            end

            if((fault==1 || fault==2) && !legacy_drain) check(drain_entries==1 && drain_residence>0,"read error traverses ERR_DRAIN exactly once");
            $display("OBS: R4 tb=full case=%0d leg=%0d raw=%0d words=%0d discarded=%0d read_fall=%0d cycles=%0d done=%b error=%0d origin=%0d entries=%0d residence=%0d",
                case_id,leg,r1+r2,in_words+fc_words,drain_discarded,read_fall-began,finished-began,status_done,status_error,drain_from,drain_entries,drain_residence);
            $display("PASS: T-06 INFER case=%0d leg=%0d name=%s cycles=%0d enc_delay=%0d input_words=%0d FC_words=%0d FC_starts=%0d FC_cycles=%0d/%0d/%0d input_AR=%0d FC_AR=%0d full=%0d AW=%0d W=%0d ready_samples=%0d ready_max_run=%0d B=%0d B_after_last_W=%0d pose_bytes=%0d output=%08h done=%b error=%0d violations=0",
                case_id,leg,case_name,finished-began,encoder.delay_cycles,in_words,fc_words,fc_starts,fc_cycles[0],fc_cycles[1],fc_cycles[2],
                ar1,ar2,full_cycles,aw_count,w_count,ready_count,max_ready_run,b_count,last_b-last_w,w_count*8,output_base,status_done,status_error);
        end
    endtask
    task common_reset;
        begin
            @(negedge clk);active=0;reg_start=0;resetn=0;cfg_ok=0;diagnostic_write=0;diagnostic_start=0;
            repeat(3) @(negedge clk);
            check(!status_busy && !mem_rd_busy && !mem_wr_busy && status_error==0 && !fc.active && fc.count==0 &&
                  ctrl.load_base_reg==0 && ctrl.ld2_addr_reg==0 && ctrl.fc1_addr_reg==0,"common synchronous reset clears engines and address cache");
            resetn=1;
        end
    endtask
    task probe_rd_fault;
        integer held_words,held_raw,held_ar;
        begin
            start_infer;
            @(posedge clk);#2;@(negedge clk);reg_start=0;
            while(ctrl.state_reg!=11 || dut.rd_state!=3'd4) begin
                @(posedge clk);#2;check(cycle-began<200,"RD_FAULT and ERR_DRAIN entry deadline");
            end
            held_words=input_ram.write_count;held_raw=r1;held_ar=ar1;
            // This is a deliberately unfinished AXI request. No check_quiescent
            // until AFTER the coordinated testbench reset; no expected violation.
            repeat(2000) begin
                @(posedge clk);#2;
                check(ctrl.state_reg==11 && dut.rd_state==4 && status_busy && mem_rd_busy &&
                    mem_rd_err && !status_done && status_error==0 && ctrl.run_error_reg==4,
                    "R5 RD_FAULT holds busy while STATUS.error remains ZERO");
                check(input_ram.write_count==held_words && r1==held_raw && ar1==held_ar &&
                    enc_starts==0 && fc_starts==0 && mem_rd_ready,"R5 consumers quiet and no false completion/timeout");
            end
            check(memory.injection_count-inject_before==1 && memory.rlast_injected>0 &&
                drain_entries==1 && memory.violation_count==0,"R5 one malformed RLAST, no master violation");
            $display("PASS: T-07 R5 case=%0d mode=%0d held_cycles=2000 state=%0d M00_state=%0d busy=%b STATUS_error=%0d internal_error=%0d raw=%0d RAM_words=%0d AXI_C12_violations=0",
                case_id,fault-3,ctrl.state_reg,dut.rd_state,status_busy,status_error,ctrl.run_error_reg,held_raw,held_words);
            common_reset;memory.check_quiescent;
            leg=1;fault=0;do_load;do_infer;
            $display("PASS: T-07 R5 case=%0d TB_common_reset_then_LOAD_then_INFER=PASS board_reset_scope=X03",case_id);
        end
    endtask
    task probe_two_engines;
        integer saved_fall;
        begin
            // B arrives well AFTER input read drain. If ERR_DRAIN checks only
            // read busy, its FINISH transition fails the per-cycle R3 assertion.
            memory.b_delay_cycles=6000;
            start_infer;diagnostic_write=1;diagnostic_addr=32'h1f000000;
            output_base=diagnostic_addr;expected_pose={3{DIAGNOSTIC_WORD}};
            fork
                wait_finish;
                begin
                    wait(mem_rd_busy);@(negedge clk);diagnostic_start=1;
                    @(negedge clk);diagnostic_start=0;
                end
            join
            check(drain_entries==1 && both_busy_cycles>0 && write_only_cycles>0 &&
                !status_done && status_error==4 && !mem_rd_busy && !mem_wr_busy,
                "R3 two real M00 engines: wait for read AND delayed B, then error4");
            check(ar1==90 && r1==1440 && in_words==21 && enc_starts==0 && fc_starts==0 &&
                wr_starts==0 && aw_count==1 && w_count==3 && b_count==1 && ready_count==3,
                "R3 diagnostic write is external TB producer; Top starts no compute/write");
            for(integer k=0;k<3;k=k+1) check(memory.mem_word(diagnostic_addr+8*k)===DIAGNOSTIC_WORD,
                "R3 diagnostic write data intact during read drain");
            check(memory.mem_word(diagnostic_addr-8)===UNWRITTEN && memory.mem_word(diagnostic_addr+24)===UNWRITTEN,
                "R3 diagnostic write guards intact");
            $display("PASS: T-07 R3 case=12 both_busy_cycles=%0d read_idle_write_busy_cycles=%0d read_fall=%0d B_accept=%0d Top_finish=%0d discarded=%0d W=3 B=1 done=%b error=%0d violations=0",
                both_busy_cycles,write_only_cycles,read_fall-began,last_b-began,finished-began,drain_discarded,status_done,status_error);
            common_reset;fault=0;leg=1;memory.b_delay_cycles=0;do_load;do_infer;
        end
    endtask
    task automatic run_case(input integer id);
        begin
            case_id=id;leg=0;fault=0;restart_probe=0;common_reset;
            encoder.delay_cycles=5;encoder.done_width_cycles=1;
            fc.consume_mode=0;fc.consume_period=4;fc.done_mode=0;fc.done_delay_cycles=5;fc.done_width_cycles=1;
            fc.fc2_delay_cycles=3;fc.fc3_delay_cycles=4;fc.fc2_done_width_cycles=1;fc.fc3_done_width_cycles=1;
            memory.ar_ready_mode=0;memory.ar_gap_cycles=0;memory.r_gap_cycles=0;memory.ddr_latency_cycles=0;
            memory.aw_ready_mode=0;memory.aw_gap_cycles=0;memory.w_ready_mode=0;memory.w_gap_cycles=0;memory.b_delay_cycles=0;
            case(id)
                0:case_name="normal_repeat";
                1:begin case_name="minimum_FC_delay";fc.done_delay_cycles=0;fc.fc2_delay_cycles=0;fc.fc3_delay_cycles=0;end
                2:begin case_name="delayed_FC";fc.done_delay_cycles=25;fc.fc2_delay_cycles=50;fc.fc3_delay_cycles=100;end
                3:begin case_name="level_done_repeat";fc.done_width_cycles=0;fc.fc2_done_width_cycles=0;fc.fc3_done_width_cycles=0;end
                4:begin case_name="write_stall_page_end";memory.aw_ready_mode=1;memory.aw_gap_cycles=8;
                    memory.w_ready_mode=1;memory.w_gap_cycles=4;memory.b_delay_cycles=20;end
                5:begin case_name="input_error_restart";fault=1;end
                6:begin case_name="FC1_error_reset_recovery";fault=2;fc.consume_mode=1;end
                7:begin case_name="write_error_restart";fault=3;memory.b_delay_cycles=12;end
                8:begin case_name="measured_Encoder_delay";encoder.delay_cycles=1278890;end
                9:begin case_name="FIFO_and_read_stall";fc.consume_mode=1;memory.ar_ready_mode=1;memory.ar_gap_cycles=7;memory.r_gap_cycles=1;end
                10:begin case_name="early_RLAST_fault";fault=4;end
                11:begin case_name="missing_RLAST_fault";fault=5;end
                12:begin case_name="read_write_outstanding_drain";fault=1;end
                default:$fatal(1,"invalid CASE");
            endcase
            memory.mem_fill(LOAD_BASE,5936,S1);memory.mem_fill(LOAD_BASE+5936,393216,SW);
            memory.mem_fill(LOAD_BASE+399152,23840,S2);memory.mem_fill(INPUT_BASE,11520,SI);
            do_load;
            if(id==10 || id==11) probe_rd_fault;
            else if(id==12) probe_two_engines;
            else do_infer;
            if(id==0 || id==3) begin
                leg=1;fault=0;do_infer;
                $display("PASS: T-06 Q6 case=%0d restart_without_reset=PASS input_words=1440 FC_words=49152 pose_bytes=24",id);
            end
            if(id==5 || id==6 || id==7) begin
                common_reset;leg=(id==6?2:1);fault=0;fc.consume_mode=0;do_load;do_infer;
                $display("PASS: T-07 D08 recovery case=%0d common_reset_then_LOAD_then_INFER=PASS input_words=1440 FC_words=49152 pose_bytes=24",id);
            end
            cases_done=cases_done+1;
        end
    endtask
    initial begin #100000000;$fatal(1,"FAIL: T-06 global deadline");end
    initial begin
        events=$fopen("top_full_events.csv","w");check(events!=0,"open trace");
        $fdisplay(events,"case,leg,phase,cycle,state,read_busy,write_busy,fc_start,fc_done,fc_sel,wr_ready,beat,FC_words,W_words");
        preload_read_fixture;
        if($value$plusargs("CASE=%d",selected)) begin
            check(selected>=0 && selected<=LAST_CASE,"valid CASE selector");run_case(selected);
        end else for(integer j=0;j<=(legacy_drain?9:LAST_CASE);j=j+1) run_case(j);
        $display("PASS: T-06 Q1-Q6 ALL SELECTED cases=%0d INFER_runs=%0d selector=%0d AXI_C12_violations=%0d",cases_done,tests,selected,memory.violation_count);
        $fclose(events);$finish;
    end
endmodule
