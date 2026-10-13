`timescale 1ns/1ps
// Pin-compatible top for the validated monolithic Ridge AXI4-Lite IP.
// Original parameter values, reset semantics, register map, and FSM cycles retained.
module ridge_axi_v1 #(
    parameter integer N_FEATURES = 955,
    parameter integer N_CLASSES = 11,
    parameter integer N_WWORDS = 5253,
    parameter integer N_XWORDS = 478,
    parameter [31:0] CORE_ID = 32'h52444731
)(
    input wire aclk, input wire aresetn,
    input wire [15:0] s_axi_awaddr, input wire s_axi_awvalid, output wire s_axi_awready,
    input wire [31:0] s_axi_wdata, input wire [3:0] s_axi_wstrb,
    input wire s_axi_wvalid, output wire s_axi_wready,
    output wire [1:0] s_axi_bresp, output wire s_axi_bvalid, input wire s_axi_bready,
    input wire [15:0] s_axi_araddr, input wire s_axi_arvalid, output wire s_axi_arready,
    output wire [31:0] s_axi_rdata, output wire [1:0] s_axi_rresp,
    output wire s_axi_rvalid, input wire s_axi_rready
);
    // This is an intentionally fixed 955-feature/11-class model contract.
    // Keep defaults and identical top-level ports for compatibility with the existing BD.
    wire wr_ok, wr_error;
    wire [31:0] wr_error_code, wr_data;
    wire [15:0] wr_addr;
    wire start_ok, commit_ok, commit_incomplete, clear_ok;
    wire [31:0] wptr, wcount, bptr, bcount, xptr, xcount, sptr;
    wire bias_low_valid;
    wire signed [63:0] bias0, bias_next;
    wire [31:0] w_read_q, x_read_q;
    wire [63:0] selected_score;
    wire [3:0] result_estimator, result_wire;
    wire model_valid, busy, done, error_flag;
    wire [31:0] error_code, cycles;
    wire [3:0] class_idx;
    wire [9:0] feature_idx;
    wire [13:0] weight_idx;
    wire f_fetch, f_mul, f_mac, f_eval, last_feature, last_class, class_next;
    wire signed [63:0] accumulator, sum_next, best_score;

    ridge_axi_slave #(.N_WWORDS(N_WWORDS), .N_XWORDS(N_XWORDS), .N_CLASSES(N_CLASSES),
                      .CORE_ID(CORE_ID)) u_axi (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .wptr(wptr), .wcount(wcount), .bptr(bptr), .bcount(bcount),
        .xptr(xptr), .xcount(xcount), .bias_low_valid(bias_low_valid),
        .sptr(sptr), .selected_score(selected_score),
        .result_estimator(result_estimator), .result_wire(result_wire),
        .model_valid(model_valid), .busy(busy), .done(done),
        .error_flag(error_flag), .error_code(error_code), .cycles(cycles),
        .wr_ok(wr_ok), .wr_addr(wr_addr), .wr_data(wr_data),
        .wr_error(wr_error), .wr_error_code(wr_error_code),
        .start_ok(start_ok), .commit_ok(commit_ok),
        .commit_incomplete(commit_incomplete), .clear_ok(clear_ok)
    );

    ridge_model_mem #(.N_WWORDS(N_WWORDS), .N_CLASSES(N_CLASSES)) u_model (
        .aclk(aclk), .aresetn(aresetn), .wr_ok(wr_ok), .wr_addr(wr_addr), .wr_data(wr_data),
        .fetch(f_fetch), .weight_idx(weight_idx), .class_idx(class_idx),
        .wptr(wptr), .wcount(wcount), .bptr(bptr), .bcount(bcount),
        .bias_low_valid(bias_low_valid), .w_read_q(w_read_q),
        .bias0(bias0), .bias_next(bias_next)
    );
    ridge_feature_mem #(.N_XWORDS(N_XWORDS)) u_feature (
        .aclk(aclk), .aresetn(aresetn), .wr_ok(wr_ok), .wr_addr(wr_addr), .wr_data(wr_data),
        .start_ok(start_ok), .fetch(f_fetch), .feature_idx(feature_idx),
        .xptr(xptr), .xcount(xcount), .x_read_q(x_read_q)
    );
    ridge_ctrl #(.N_FEATURES(N_FEATURES), .N_CLASSES(N_CLASSES)) u_ctrl (
        .aclk(aclk), .aresetn(aresetn), .wr_ok(wr_ok), .wr_addr(wr_addr),
        .wr_error(wr_error), .wr_error_code(wr_error_code),
        .start_ok(start_ok), .commit_ok(commit_ok),
        .commit_incomplete(commit_incomplete), .clear_ok(clear_ok),
        .model_valid(model_valid), .busy(busy), .done(done),
        .error_flag(error_flag), .error_code(error_code), .cycles(cycles),
        .class_idx(class_idx), .feature_idx(feature_idx), .weight_idx(weight_idx),
        .f_fetch(f_fetch), .f_mul(f_mul), .f_mac(f_mac), .f_eval(f_eval),
        .last_feature(last_feature), .last_class(last_class), .class_next(class_next)
    );
    ridge_mac u_mac (
        .aclk(aclk), .aresetn(aresetn), .start_ok(start_ok),
        .f_mul(f_mul), .f_mac(f_mac), .class_next(class_next),
        .w_read_q(w_read_q), .x_read_q(x_read_q),
        .weight_idx(weight_idx), .feature_idx(feature_idx),
        .bias0(bias0), .bias_next(bias_next),
        .accumulator(accumulator), .sum_next(sum_next)
    );
    ridge_result #(.N_CLASSES(N_CLASSES)) u_result (
        .aclk(aclk), .aresetn(aresetn), .wr_ok(wr_ok), .wr_addr(wr_addr), .wr_data(wr_data),
        .f_mac(f_mac), .last_feature(last_feature), .f_eval(f_eval), .last_class(last_class),
        .class_idx(class_idx), .accumulator(accumulator), .sum_next(sum_next),
        .sptr(sptr), .selected_score(selected_score),
        .result_estimator(result_estimator), .result_wire(result_wire),
        .best_score(best_score)
    );
endmodule
