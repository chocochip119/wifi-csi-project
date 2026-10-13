`timescale 1ns/1ps
// AXI4-Lite handshakes, address decoder, command validation and MMIO read mux.
// AW and W remain independently buffered; B/R permit one outstanding response.
module ridge_axi_slave #(
    parameter integer N_WWORDS=5253, N_XWORDS=478, N_CLASSES=11,
    parameter [31:0] CORE_ID=32'h52444731
)(
    input wire aclk, aresetn,
    input wire [15:0] s_axi_awaddr, input wire s_axi_awvalid, output wire s_axi_awready,
    input wire [31:0] s_axi_wdata, input wire [3:0] s_axi_wstrb,
    input wire s_axi_wvalid, output wire s_axi_wready,
    output reg [1:0] s_axi_bresp, output reg s_axi_bvalid, input wire s_axi_bready,
    input wire [15:0] s_axi_araddr, input wire s_axi_arvalid, output wire s_axi_arready,
    output reg [31:0] s_axi_rdata, output reg [1:0] s_axi_rresp,
    output reg s_axi_rvalid, input wire s_axi_rready,
    input wire [31:0] wptr, wcount, bptr, bcount, xptr, xcount, sptr,
    input wire bias_low_valid,
    input wire [63:0] selected_score,
    input wire [3:0] result_estimator, result_wire,
    input wire model_valid, busy, done, error_flag,
    input wire [31:0] error_code, cycles,
    output wire wr_ok, output wire [15:0] wr_addr, output wire [31:0] wr_data,
    output wire wr_error, output reg [31:0] wr_error_code,
    output wire start_ok, commit_ok, commit_incomplete, clear_ok
);
    localparam [15:0] REG_CONTROL=16'h0000, REG_STATUS=16'h0004,
        REG_ERR=16'h0008, REG_WPTR=16'h000c, REG_WDATA=16'h0010,
        REG_BPTR=16'h0014, REG_BLO=16'h0018, REG_BHI=16'h001c,
        REG_XPTR=16'h0020, REG_XDATA=16'h0024,
        REG_RESULT=16'h0028, REG_SPTR=16'h002c,
        REG_SLO=16'h0030, REG_SHI=16'h0034,
        REG_ID=16'h0038, REG_CYCLES=16'h003c,
        REG_WCOUNT=16'h0040, REG_BCOUNT=16'h0044, REG_XCOUNT=16'h0048;
    localparam [31:0] E_NONE=0, E_INCOMPLETE_MODEL=1, E_INCOMPLETE_INPUT=2,
        E_BUSY=3, E_BAD_WRITE=4, E_MODEL_CHANGE_BUSY=5;
    reg aw_pending, w_pending;
    reg [15:0] aw_addr_q;
    reg [31:0] w_data_q;
    reg [3:0] w_strb_q;
    assign s_axi_awready = !aw_pending && !s_axi_bvalid;
    assign s_axi_wready = !w_pending && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;
    wire do_write = aw_pending && w_pending && !s_axi_bvalid;
    wire [15:0] wa = {aw_addr_q[15:2], 2'b00};

    always @* begin
        wr_error_code=E_NONE;
        if (do_write) begin
            if (aw_addr_q[1:0]!=2'b00 || w_strb_q!=4'b1111)
                wr_error_code=E_BAD_WRITE;
            else case (wa)
                REG_CONTROL: begin
                    if ((w_data_q & 32'hfffffff8)!=0 ||
                        (w_data_q[2] && (w_data_q[1] || w_data_q[0])) ||
                        (w_data_q[1] && w_data_q[0]))
                        wr_error_code=E_BAD_WRITE;
                    else if (w_data_q[1]) begin
                        if (busy) wr_error_code=E_MODEL_CHANGE_BUSY;
                        else if (wcount!=N_WWORDS || bcount!=N_CLASSES || bias_low_valid)
                            wr_error_code=E_INCOMPLETE_MODEL;
                    end else if (w_data_q[0]) begin
                        if (busy) wr_error_code=E_BUSY;
                        else if (!model_valid) wr_error_code=E_INCOMPLETE_MODEL;
                        else if (xcount!=N_XWORDS) wr_error_code=E_INCOMPLETE_INPUT;
                    end
                end
                REG_WPTR:  if (busy) wr_error_code=E_MODEL_CHANGE_BUSY;
                           else if (w_data_q>=N_WWORDS) wr_error_code=E_BAD_WRITE;
                REG_WDATA: if (busy) wr_error_code=E_MODEL_CHANGE_BUSY;
                           else if (wptr>=N_WWORDS) wr_error_code=E_BAD_WRITE;
                REG_BPTR:  if (busy) wr_error_code=E_MODEL_CHANGE_BUSY;
                           else if (w_data_q>=N_CLASSES) wr_error_code=E_BAD_WRITE;
                REG_BLO:   if (busy) wr_error_code=E_MODEL_CHANGE_BUSY;
                           else if (bptr>=N_CLASSES) wr_error_code=E_BAD_WRITE;
                REG_BHI:   if (busy) wr_error_code=E_MODEL_CHANGE_BUSY;
                           else if (bptr>=N_CLASSES || !bias_low_valid) wr_error_code=E_BAD_WRITE;
                REG_XPTR:  if (busy) wr_error_code=E_BUSY;
                           else if (w_data_q>=N_XWORDS) wr_error_code=E_BAD_WRITE;
                REG_XDATA: if (busy) wr_error_code=E_BUSY;
                           else if (xptr>=N_XWORDS) wr_error_code=E_BAD_WRITE;
                REG_SPTR:  if (w_data_q>=N_CLASSES) wr_error_code=E_BAD_WRITE;
                default:   wr_error_code=E_BAD_WRITE;
            endcase
        end
    end
    assign wr_error = do_write && (wr_error_code!=E_NONE);
    assign wr_ok = do_write && !wr_error;
    assign wr_addr = wa;
    assign wr_data = w_data_q;
    assign clear_ok = wr_ok && wa==REG_CONTROL && w_data_q[2];
    assign commit_ok = wr_ok && wa==REG_CONTROL && w_data_q[1];
    assign start_ok = wr_ok && wa==REG_CONTROL && w_data_q[0];
    assign commit_incomplete = do_write && wa==REG_CONTROL &&
                               aw_addr_q[1:0]==2'b00 && w_strb_q==4'b1111 &&
                               w_data_q==32'h2 && !busy &&
                               wr_error_code==E_INCOMPLETE_MODEL;

    always @(posedge aclk) begin
        if (!aresetn) begin
            aw_pending<=0; w_pending<=0;
            aw_addr_q<=0; w_data_q<=0; w_strb_q<=0;
            s_axi_bvalid<=0; s_axi_bresp<=0;
            s_axi_rvalid<=0; s_axi_rresp<=0; s_axi_rdata<=0;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                aw_pending<=1; aw_addr_q<=s_axi_awaddr;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                w_pending<=1; w_data_q<=s_axi_wdata; w_strb_q<=s_axi_wstrb;
            end
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid<=0;
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid<=0;
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid<=1; s_axi_rresp<=2'b00;
                if (s_axi_araddr[1:0]!=2'b00) begin
                    s_axi_rdata<=0; s_axi_rresp<=2'b10;
                end else case (s_axi_araddr)
                    REG_CONTROL: s_axi_rdata<=0;
                    REG_STATUS: s_axi_rdata<={28'd0,model_valid,error_flag,done,busy};
                    REG_ERR: s_axi_rdata<=error_code;
                    REG_WPTR: s_axi_rdata<=wptr;
                    REG_BPTR: s_axi_rdata<=bptr;
                    REG_XPTR: s_axi_rdata<=xptr;
                    REG_RESULT: if(done) s_axi_rdata<={24'd0,result_wire,result_estimator};
                                else begin s_axi_rdata<=0; s_axi_rresp<=2'b10; end
                    REG_SPTR: s_axi_rdata<=sptr;
                    REG_SLO: if(done) s_axi_rdata<=selected_score[31:0];
                             else begin s_axi_rdata<=0; s_axi_rresp<=2'b10; end
                    REG_SHI: if(done) s_axi_rdata<=selected_score[63:32];
                             else begin s_axi_rdata<=0; s_axi_rresp<=2'b10; end
                    REG_ID: s_axi_rdata<=CORE_ID;
                    REG_CYCLES: s_axi_rdata<=cycles;
                    REG_WCOUNT: s_axi_rdata<=wcount;
                    REG_BCOUNT: s_axi_rdata<=bcount;
                    REG_XCOUNT: s_axi_rdata<=xcount;
                    default: begin s_axi_rdata<=0; s_axi_rresp<=2'b10; end
                endcase
            end
            if (do_write) begin
                aw_pending<=0; w_pending<=0;
                s_axi_bvalid<=1;
                s_axi_bresp<=wr_error ? 2'b10 : 2'b00;
            end
        end
    end
endmodule
