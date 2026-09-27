`timescale 1ns / 1ps

// X-02a simulation integration: three production blocks and one TB-only FC.
// Pure wiring, 04_pose_cnn ports; no AXI bus or extra storage/control logic.
// NOT a synthesis top while u_fc is fc_stub. D09 selects remain inside core.
module pose_cnn (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         reg_start,
    input  wire         reg_clear_status,
    input  wire [31:0]  reg_cmd,
    input  wire [31:0]  reg_input_addr,
    input  wire [31:0]  reg_weight_addr,
    input  wire [31:0]  reg_output_addr,
    output wire         status_busy,
    output wire         status_done,
    output wire [3:0]   status_error,
    output wire         cfg_ok,
    output wire [31:0]  output_scale_bits,
    output wire         mem_rd_start,
    output wire [31:0]  mem_rd_addr,
    output wire [19:0]  mem_rd_bytes,
    input  wire         mem_rd_busy,
    input  wire [63:0]  mem_rd_data,
    input  wire         mem_rd_valid,
    output wire         mem_rd_ready,
    input  wire         mem_rd_err,
    output wire         mem_wr_start,
    output wire [31:0]  mem_wr_addr,
    output wire [19:0]  mem_wr_bytes,
    input  wire         mem_wr_busy,
    output wire [63:0]  mem_wr_data,
    input  wire         mem_wr_ready,
    input  wire         mem_wr_err
);
    wire loader_start;
    wire loader_done;
    wire loader_err;
    wire [63:0] ld_data;
    wire ld_valid;
    wire ld_ready;
    wire param_sel_fc;
    wire lut_sel_fc;
    wire enc_start;
    wire enc_done;
    wire in_we;
    wire [10:0] in_waddr;
    wire [63:0] in_wdata;
    wire fc_start;
    wire fc_done;
    wire [1:0] fc_sel;
    wire fifo_we;
    wire [63:0] fifo_wdata;
    wire fifo_full;
    wire [191:0] pose_data;
    wire [31:0] pool_mult;
    wire [31:0] pool_shift;
    wire [8:0] conv_raddr;
    wire [127:0] conv_rdata;
    wire [8:0] enc_param_raddr;
    wire [95:0] enc_param_rdata;
    wire [9:0] enc_lut_raddr;
    wire [7:0] enc_lut_rdata;
    wire [8:0] fc_param_raddr;
    wire [95:0] fc_param_rdata;
    wire [9:0] fc_lut_raddr;
    wire [7:0] fc_lut_rdata;
    wire [11:0] fcw_raddr;
    wire [63:0] fcw_rdata;
    wire [8:0] flat_raddr;
    wire [63:0] flat_rdata;

    pose_cnn_ctrl u_ctrl (
        .clk(clk),
        .rst_n(rst_n),
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
        .param_sel_fc(param_sel_fc),
        .lut_sel_fc(lut_sel_fc),
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

    weight_param_loader u_loader (
        .clk(clk),
        .rst_n(rst_n),
        .loader_start(loader_start),
        .loader_done(loader_done),
        .loader_err(loader_err),
        .ld_data(ld_data),
        .ld_valid(ld_valid),
        .ld_ready(ld_ready),
        .cfg_ok(cfg_ok),
        .pool_mult(pool_mult),
        .pool_shift(pool_shift),
        .output_scale_bits(output_scale_bits),
        .param_sel_fc(param_sel_fc),
        .lut_sel_fc(lut_sel_fc),
        .conv_raddr(conv_raddr),
        .conv_rdata(conv_rdata),
        .enc_param_raddr(enc_param_raddr),
        .enc_param_rdata(enc_param_rdata),
        .enc_lut_raddr(enc_lut_raddr),
        .enc_lut_rdata(enc_lut_rdata),
        .fc_param_raddr(fc_param_raddr),
        .fc_param_rdata(fc_param_rdata),
        .fc_lut_raddr(fc_lut_raddr),
        .fc_lut_rdata(fc_lut_rdata),
        .fcw_raddr(fcw_raddr),
        .fcw_rdata(fcw_rdata)
    );

    CNN_Encoder u_encoder (
        .clk(clk),
        .rst_n(rst_n),
        .enc_start(enc_start),
        .enc_done(enc_done),
        .in_we(in_we),
        .in_waddr(in_waddr),
        .in_wdata(in_wdata),
        .conv_raddr(conv_raddr),
        .conv_rdata(conv_rdata),
        .enc_param_raddr(enc_param_raddr),
        .enc_param_rdata(enc_param_rdata),
        .enc_lut_raddr(enc_lut_raddr),
        .enc_lut_rdata(enc_lut_rdata),
        .pool_mult(pool_mult),
        .pool_shift(pool_shift),
        .feat_raddr(flat_raddr),
        .feat_rdata(flat_rdata)
    );

    fc_stub u_fc (
        .clk(clk),
        .resetn(rst_n),
        .fc_start(fc_start),
        .fc_sel(fc_sel),
        .fifo_we(fifo_we),
        .fifo_wdata(fifo_wdata),
        .fifo_full(fifo_full),
        .fc_done(fc_done),
        .pose_data(pose_data),
        .fc_param_raddr(fc_param_raddr),
        .fc_param_rdata(fc_param_rdata),
        .fc_lut_raddr(fc_lut_raddr),
        .fc_lut_rdata(fc_lut_rdata),
        .fcw_raddr(fcw_raddr),
        .fcw_rdata(fcw_rdata),
        .flat_raddr(flat_raddr),
        .flat_rdata(flat_rdata)
    );
endmodule
