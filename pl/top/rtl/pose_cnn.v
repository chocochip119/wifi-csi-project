`timescale 1ns / 1ps

// CNN core integration. One compile-time RX value configures every RX-dependent
// block; no runtime RX configuration is used.
module pose_cnn #(
    parameter integer RX = 5
) (
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
    localparam integer IN_WADDR_W = (RX * 480 <= 1) ? 1 : $clog2(RX * 480);
    localparam integer FLAT_ADDR_WIDTH = (RX * 128 <= 1) ? 1 : $clog2(RX * 128);

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
    wire [IN_WADDR_W-1:0] in_waddr;
    wire [63:0] in_wdata;
    wire fc_start;
    wire fc_done_raw;
    wire fc_done_ctrl;
    wire [1:0] fc_sel;
    wire fifo_we;
    wire [63:0] fifo_wdata;
    wire fifo_full;
    reg [191:0] pose_data;
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
    wire [FLAT_ADDR_WIDTH-1:0] flat_raddr;
    wire [63:0] flat_rdata;

    pose_cnn_ctrl #(
        .RX(RX)
    ) u_ctrl (
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
        .fc_done(fc_done_ctrl),
        .fc_sel(fc_sel),
        .fifo_we(fifo_we),
        .fifo_wdata(fifo_wdata),
        .fifo_full(fifo_full),
        .pose_data(pose_data)
    );

    weight_param_loader #(
        .RX(RX)
    ) u_loader (
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

    CNN_Encoder #(
        .RX(RX)
    ) u_encoder (
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

    wire fc_fifo_empty;
    wire [4:0] pose_raddr;
    wire [7:0] pose_rdata;

    fc_top #(
        .RX_NUM(RX),
        .WORDS_PER_RX(128),
        .FC1_OUT_NUM(128),
        .FC2_OUT_NUM(128),
        .FC3_OUT_NUM(24),
        .FC1_PARAM_BASE(48),
        .FC2_PARAM_BASE(176),
        .FC3_PARAM_BASE(304)
    ) u_fc (
        .clk(clk),
        .rst_n(rst_n),
        .fc_start(fc_start),
        .fc_sel(fc_sel),
        .fc_done(fc_done_raw),
        .feat_raddr(flat_raddr),
        .feat_rdata(flat_rdata),
        .fc1_fifo_we(fifo_we),
        .fc1_fifo_wdata(fifo_wdata),
        .fc1_fifo_full(fifo_full),
        .fc1_fifo_empty(fc_fifo_empty),
        .fc_param_raddr(fc_param_raddr),
        .fc_param_rdata(fc_param_rdata),
        .fc_lut_raddr(fc_lut_raddr),
        .fc_lut_rdata(fc_lut_rdata),
        .fcw_raddr(fcw_raddr),
        .fcw_rdata(fcw_rdata),
        .pose_raddr(pose_raddr),
        .pose_rdata(pose_rdata)
    );

    // fc_top exposes a synchronous byte read port for its 24-byte result.
    // Keep the Controller FSM unchanged: delay only the FC3 done indication
    // while collecting those bytes into the Controller's existing 192-bit bus.
    reg [1:0] fc_layer_reg;
    reg pose_collect_active;
    reg pose_collect_wait;
    reg [4:0] pose_raddr_reg;
    reg [4:0] pose_capture_index;
    reg fc3_done_reg;

    assign pose_raddr = pose_raddr_reg;
    assign fc_done_ctrl = ((fc_layer_reg != 2'd2) && fc_done_raw) || fc3_done_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fc_layer_reg <= 2'd0;
            pose_collect_active <= 1'b0;
            pose_collect_wait <= 1'b0;
            pose_raddr_reg <= 5'd0;
            pose_capture_index <= 5'd0;
            pose_data <= 192'd0;
            fc3_done_reg <= 1'b0;
        end else begin
            fc3_done_reg <= 1'b0;
            if (fc_start)
                fc_layer_reg <= fc_sel;

            if (!pose_collect_active) begin
                pose_collect_wait <= 1'b0;
                if (fc_done_raw && (fc_layer_reg == 2'd2)) begin
                    pose_collect_active <= 1'b1;
                    pose_collect_wait <= 1'b1;
                    pose_raddr_reg <= 5'd0;
                    pose_capture_index <= 5'd0;
                end
            end else if (pose_collect_wait) begin
                pose_collect_wait <= 1'b0;
            end else begin
                pose_data[{pose_capture_index, 3'b000} +: 8] <= pose_rdata;
                if (pose_capture_index == 5'd23) begin
                    pose_collect_active <= 1'b0;
                    fc3_done_reg <= 1'b1;
                end else begin
                    pose_capture_index <= pose_capture_index + 5'd1;
                    pose_raddr_reg <= pose_raddr_reg + 5'd1;
                    pose_collect_wait <= 1'b1;
                end
            end
        end
    end
endmodule
