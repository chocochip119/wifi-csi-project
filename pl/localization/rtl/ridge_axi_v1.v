`timescale 1ns/1ps
// Ridge accelerator: 955 signed Q7 inputs, 11 classes, 10505 signed 16-bit
// coefficients and 11 signed 64-bit Q(FX+FW) biases.
// 32-bit AXI4-Lite, independent AW and W acceptance, one outstanding B/R.
// All register offsets are 32-bit aligned. Clock: recommended 100 MHz.
// No internal memory initialization: model must be uploaded by PS after reset.
module ridge_axi_v1 #(
    parameter integer N_FEATURES = 955,
    parameter integer N_CLASSES = 11,
    parameter integer N_WWORDS = 5253,
    parameter integer N_XWORDS = 478,
    parameter [31:0] CORE_ID = 32'h52444731
)(
    input wire aclk,
    input wire aresetn,
    input wire [15:0] s_axi_awaddr,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    input wire [31:0] s_axi_wdata,
    input wire [3:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    output reg [1:0] s_axi_bresp,
    output reg s_axi_bvalid,
    input wire s_axi_bready,
    input wire [15:0] s_axi_araddr,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    output reg [31:0] s_axi_rdata,
    output reg [1:0] s_axi_rresp,
    output reg s_axi_rvalid,
    input wire s_axi_rready
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
    localparam [2:0] S_IDLE=0, S_FETCH=1, S_MUL=2, S_MAC=3, S_EVAL=4;

    // Synthesizable true synchronous reads and independent AXI writes.
    (* ram_style = "block" *) reg [31:0] weight_ram [0:N_WWORDS-1];
    (* ram_style = "block" *) reg [31:0] feature_ram [0:N_XWORDS-1];
    reg signed [63:0] biases [0:N_CLASSES-1];
    reg signed [63:0] scores [0:N_CLASSES-1];

    reg [31:0] wptr, xptr, bptr, sptr;
    reg [31:0] wcount, bcount, xcount;
    reg [31:0] bias_low_latch;
    reg bias_low_valid;
    reg model_valid, busy, done, error_flag;
    reg [31:0] error_code;
    reg [3:0] result_estimator, result_wire;
    reg [31:0] cycles;

    reg aw_pending, w_pending;
    reg [15:0] aw_addr_q;
    reg [31:0] w_data_q;
    reg [3:0] w_strb_q;
    assign s_axi_awready = !aw_pending && !s_axi_bvalid;
    assign s_axi_wready = !w_pending && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;
    wire do_write = aw_pending && w_pending && !s_axi_bvalid;
    wire [15:0] wa = {aw_addr_q[15:2],2'b00};

    reg [2:0] state;
    reg [3:0] class_idx, best_idx;
    reg [9:0] feature_idx;
    reg [13:0] weight_idx;
    reg [31:0] w_read_q, x_read_q;
    reg signed [31:0] product_q;
    reg signed [63:0] accumulator, best_score;
    wire signed [15:0] wt = weight_idx[0] ? $signed(w_read_q[31:16]) : $signed(w_read_q[15:0]);
    wire signed [15:0] xt = feature_idx[0] ? $signed(x_read_q[31:16]) : $signed(x_read_q[15:0]);
    wire signed [31:0] product = wt * xt;
    wire signed [63:0] product_ext = {{32{product_q[31]}},product_q};
    wire signed [63:0] sum_next = accumulator + product_ext;

    integer i;
    always @(posedge aclk) begin
        if (!aresetn) begin
            aw_pending <= 1'b0; w_pending <= 1'b0;
            aw_addr_q <= 16'd0; w_data_q <= 32'd0; w_strb_q <= 4'd0;
            s_axi_bvalid <= 1'b0; s_axi_bresp <= 2'b00;
            s_axi_rvalid <= 1'b0; s_axi_rresp <= 2'b00; s_axi_rdata <= 32'd0;
            wptr<=0; xptr<=0; bptr<=0; sptr<=0;
            wcount<=0; bcount<=0; xcount<=0;
            bias_low_latch<=0; bias_low_valid<=0;
            model_valid<=0; busy<=0; done<=0; error_flag<=0; error_code<=0;
            result_estimator<=0; result_wire<=0; cycles<=0;
            state<=S_IDLE; class_idx<=0; best_idx<=0; feature_idx<=0;
            weight_idx<=0; w_read_q<=0; x_read_q<=0; product_q<=0;
            accumulator<=0; best_score<=0;
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
                if (s_axi_araddr[1:0] != 2'b00) begin
                    s_axi_rdata<=0; s_axi_rresp<=2'b10; // no silent unaligned aliasing
                end else case (s_axi_araddr)
                    REG_CONTROL: s_axi_rdata<=0;
                    REG_STATUS:  s_axi_rdata<={28'd0,model_valid,error_flag,done,busy};
                    REG_ERR:     s_axi_rdata<=error_code;
                    REG_WPTR:    s_axi_rdata<=wptr;
                    REG_BPTR:    s_axi_rdata<=bptr;
                    REG_XPTR:    s_axi_rdata<=xptr;
                    REG_RESULT:  if (done) s_axi_rdata<={24'd0,result_wire,result_estimator};
                                 else begin s_axi_rdata<=0; s_axi_rresp<=2'b10; end
                    REG_SPTR:    s_axi_rdata<=sptr;
                    REG_SLO:     if (done) s_axi_rdata<=scores[sptr][31:0];
                                 else begin s_axi_rdata<=0; s_axi_rresp<=2'b10; end
                    REG_SHI:     if (done) s_axi_rdata<=scores[sptr][63:32];
                                 else begin s_axi_rdata<=0; s_axi_rresp<=2'b10; end
                    REG_ID:      s_axi_rdata<=CORE_ID;
                    REG_CYCLES:  s_axi_rdata<=cycles;
                    REG_WCOUNT:  s_axi_rdata<=wcount;
                    REG_BCOUNT:  s_axi_rdata<=bcount;
                    REG_XCOUNT:  s_axi_rdata<=xcount;
                    default: begin s_axi_rdata<=0; s_axi_rresp<=2'b10; end
                endcase
            end
            if (do_write) begin
                aw_pending<=0; w_pending<=0;
                s_axi_bvalid<=1; s_axi_bresp<=2'b00;
                // Reject unaligned aliases, including writes to valid register neighbors.
                if (aw_addr_q[1:0] != 2'b00) begin
                    s_axi_bresp<=2'b10; error_flag<=1; error_code<=E_BAD_WRITE;
                end else if (w_strb_q!=4'b1111) begin
                    s_axi_bresp<=2'b10; error_flag<=1; error_code<=E_BAD_WRITE;
                end else begin
                    case (wa)
                        REG_CONTROL: begin
                            // Only one command bit per transaction; reserved bits are invalid.
                            if ((w_data_q & 32'hfffffff8) != 0 ||
                                (w_data_q[2] && (w_data_q[1] || w_data_q[0])) ||
                                (w_data_q[1] && w_data_q[0])) begin
                                s_axi_bresp<=2'b10; error_flag<=1; error_code<=E_BAD_WRITE;
                            end else begin
                            if (w_data_q[2]) begin
                                done<=0; error_flag<=0; error_code<=E_NONE;
                            end
                            if (w_data_q[1]) begin  // commit initialized model
                                if (busy) begin
                                    error_flag<=1; error_code<=E_MODEL_CHANGE_BUSY;
                                    s_axi_bresp<=2'b10;
                                end else if (wcount==N_WWORDS && bcount==N_CLASSES && !bias_low_valid) begin
                                    model_valid<=1; done<=0;
                                end else begin
                                    model_valid<=0; done<=0; error_flag<=1;
                                    error_code<=E_INCOMPLETE_MODEL; s_axi_bresp<=2'b10;
                                end
                            end
                            if (w_data_q[0]) begin  // START
                                if (busy) begin
                                    error_flag<=1; error_code<=E_BUSY;
                                    s_axi_bresp<=2'b10;
                                end else if (!model_valid) begin
                                    error_flag<=1; error_code<=E_INCOMPLETE_MODEL;
                                    s_axi_bresp<=2'b10;
                                end else if (xcount!=N_XWORDS) begin
                                    error_flag<=1; error_code<=E_INCOMPLETE_INPUT;
                                    s_axi_bresp<=2'b10;
                                end else begin
                                    done<=0; error_flag<=0; error_code<=E_NONE;
                                    busy<=1; state<=S_FETCH;
                                    class_idx<=0; best_idx<=0; feature_idx<=0; weight_idx<=0;
                                    accumulator<=biases[0]; best_score<=0; cycles<=0;
                                    xcount<=0;
                                end
                            end
                            end
                        end
                        REG_WPTR: begin
                            if (busy || w_data_q>=N_WWORDS) begin
                                s_axi_bresp<=2'b10; error_flag<=1; error_code<=busy ? E_MODEL_CHANGE_BUSY : E_BAD_WRITE;
                            end else begin
                                wptr<=w_data_q; wcount<=0; model_valid<=0; done<=0;
                            end
                        end
                        REG_WDATA: begin
                            if (busy || wptr>=N_WWORDS) begin
                                s_axi_bresp<=2'b10; error_flag<=1; error_code<=busy ? E_MODEL_CHANGE_BUSY : E_BAD_WRITE;
                            end else begin
                                weight_ram[wptr]<=w_data_q;
                                wptr<=wptr+1; wcount<=wcount+1; model_valid<=0; done<=0;
                            end
                        end
                        REG_BPTR: begin
                            if (busy || w_data_q>=N_CLASSES) begin
                                s_axi_bresp<=2'b10; error_flag<=1; error_code<=busy ? E_MODEL_CHANGE_BUSY : E_BAD_WRITE;
                            end else begin
                                bptr<=w_data_q; bcount<=0; bias_low_valid<=0; model_valid<=0; done<=0;
                            end
                        end
                        REG_BLO: begin
                            if (busy || bptr>=N_CLASSES) begin
                                s_axi_bresp<=2'b10; error_flag<=1; error_code<=busy ? E_MODEL_CHANGE_BUSY : E_BAD_WRITE;
                            end else begin
                                bias_low_latch<=w_data_q; bias_low_valid<=1; model_valid<=0; done<=0;
                            end
                        end
                        REG_BHI: begin
                            if (busy || bptr>=N_CLASSES || !bias_low_valid) begin
                                s_axi_bresp<=2'b10; error_flag<=1; error_code<=busy ? E_MODEL_CHANGE_BUSY : E_BAD_WRITE;
                            end else begin
                                biases[bptr]<={w_data_q,bias_low_latch};
                                bptr<=bptr+1; bcount<=bcount+1;
                                bias_low_valid<=0; model_valid<=0; done<=0;
                            end
                        end
                        REG_XPTR: begin
                            if (busy || w_data_q>=N_XWORDS) begin
                                s_axi_bresp<=2'b10; error_flag<=1; error_code<=busy ? E_BUSY : E_BAD_WRITE;
                            end else begin
                                xptr<=w_data_q; xcount<=0; done<=0;
                            end
                        end
                        REG_XDATA: begin
                            if (busy || xptr>=N_XWORDS) begin
                                s_axi_bresp<=2'b10; error_flag<=1; error_code<=busy ? E_BUSY : E_BAD_WRITE;
                            end else begin
                                feature_ram[xptr]<=w_data_q;
                                xptr<=xptr+1; xcount<=xcount+1;
                            end
                        end
                        REG_SPTR: begin
                            if (w_data_q>=N_CLASSES) begin
                                s_axi_bresp<=2'b10; error_flag<=1; error_code<=E_BAD_WRITE;
                            end else sptr<=w_data_q;
                        end
                        default: begin
                            s_axi_bresp<=2'b10; error_flag<=1; error_code<=E_BAD_WRITE;
                        end
                    endcase
                end
            end
            // FSM: synchronous RAM fetch, registered DSP product, 64-bit
            // accumulation, then a separate per-class score evaluation.
            case (state)
                S_IDLE: ;
                S_FETCH: begin
                    w_read_q<=weight_ram[weight_idx[13:1]];
                    x_read_q<=feature_ram[feature_idx[9:1]];
                    cycles<=cycles+1;
                    state<=S_MUL;
                end
                S_MUL: begin
                    product_q<=product;
                    cycles<=cycles+1;
                    state<=S_MAC;
                end
                S_MAC: begin
                    cycles<=cycles+1;
                    weight_idx<=weight_idx+1;
                    if (feature_idx==N_FEATURES-1) begin
                        scores[class_idx]<=sum_next;
                        accumulator<=sum_next;
                        state<=S_EVAL;
                    end else begin
                        feature_idx<=feature_idx+1;
                        accumulator<=sum_next;
                        state<=S_FETCH;
                    end
                end
                S_EVAL: begin
                    cycles<=cycles+1;
                    if (class_idx==0 || accumulator>best_score) begin
                        best_score<=accumulator;
                        best_idx<=class_idx;
                    end
                        if (class_idx==N_CLASSES-1) begin
                            if (class_idx==0 || accumulator>best_score) begin
                                result_estimator<=class_idx;
                                result_wire<=class_idx==0 ? 4'd10 : class_idx-1'b1;
                            end else begin
                                result_estimator<=best_idx;
                                result_wire<=best_idx==0 ? 4'd10 : best_idx-1'b1;
                            end
                            busy<=0; done<=1; state<=S_IDLE;
                        end else begin
                            class_idx<=class_idx+1;
                            feature_idx<=0;
                            accumulator<=biases[class_idx+1];
                            state<=S_FETCH;
                        end
                end
                default: state<=S_IDLE;
            endcase
        end
    end
endmodule
