`timescale 1ns / 1ps

module fc_top #(
    parameter integer RX_NUM         = 5,
    parameter integer WORDS_PER_RX   = 128,
    parameter integer FC1_OUT_NUM    = 128,
    parameter integer FC2_OUT_NUM    = 128,
    parameter integer FC3_OUT_NUM    = 24,
    parameter integer FC1_FIFO_DEPTH = 512,
    parameter integer FLAT_WORDS     = RX_NUM * WORDS_PER_RX,
    parameter integer FLAT_ADDR_WIDTH =
        (FLAT_WORDS <= 1) ? 1 : $clog2(FLAT_WORDS),
    parameter integer FC1_PARAM_BASE = 0,
    parameter integer FC2_PARAM_BASE = 128,
    parameter integer FC3_PARAM_BASE = 256
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         fc_start,
    input  wire [1:0]                   fc_sel,
    output wire                         fc_done,

    output wire [FLAT_ADDR_WIDTH-1:0]   feat_raddr,
    input  wire [63:0]                  feat_rdata,

    input  wire                         fc1_fifo_we,
    input  wire [63:0]                  fc1_fifo_wdata,
    output wire                         fc1_fifo_full,
    output wire                         fc1_fifo_empty,

    output wire [11:0]                  fcw_raddr,
    input  wire [63:0]                  fcw_rdata,

    output reg  [8:0]                   fc_param_raddr,
    input  wire [95:0]                  fc_param_rdata,

    output wire [9:0]                   fc_lut_raddr,
    input  wire [7:0]                   fc_lut_rdata,

    input  wire [4:0]                   pose_raddr,
    output wire [7:0]                   pose_rdata
);
    // Layer ID
    localparam [1:0] FC1 = 2'd0;
    localparam [1:0] FC2 = 2'd1;
    localparam [1:0] FC3 = 2'd2;

    // Controller Signals
    wire [1:0] active_fc_sel;
    wire [FLAT_ADDR_WIDTH-1:0] flat_raddr;
    wire [4:0] hidden_raddr_ctrl;
    wire       fifo_re;
    wire [63:0] fifo_rdata;
    wire [63:0] fc1_weight_data;
    wire       mac_valid;
    wire       mac_first;
    wire       mac_last;
    wire [8:0] mac_tag;
    wire       layer_store_done;

    // FC1 Weight FIFO
    fc_fifo #(
        .DATA_WIDTH (64),
        .DEPTH      (FC1_FIFO_DEPTH)
    ) u_fc_fifo (
        .clk        (clk),
        .rst_n      (rst_n),
        .fifo_we    (fc1_fifo_we),
        .fifo_wdata (fc1_fifo_wdata),
        .fifo_full  (fc1_fifo_full),
        .fifo_re    (fifo_re),
        .fifo_rdata (fifo_rdata),
        .fifo_empty (fc1_fifo_empty)
    );

    // Flatten
    wire [63:0] flat_rdata;

    flatten #(
        .RX_NUM       (RX_NUM),
        .WORDS_PER_RX (WORDS_PER_RX),
        .FLAT_WORDS   (FLAT_WORDS),
        .ADDR_WIDTH   (FLAT_ADDR_WIDTH)
    ) u_flatten (
        .flat_raddr (flat_raddr),
        .flat_rdata (flat_rdata),
        .feat_raddr (feat_raddr),
        .feat_rdata (feat_rdata)
    );

    // Hidden RAM
    wire        hidden_we;
    wire        hidden_wbank;
    wire [6:0]  hidden_waddr;
    wire [7:0]  hidden_wdata;
    wire [63:0] hidden_rdata;

    hidden_ram u_hidden_ram (
        .clk          (clk),
        .rst_n        (rst_n),
        .hidden_we    (hidden_we),
        .hidden_wbank (hidden_wbank),
        .hidden_waddr (hidden_waddr),
        .hidden_wdata (hidden_wdata),
        .hidden_rbank (hidden_raddr_ctrl[4]),
        .hidden_raddr (hidden_raddr_ctrl[3:0]),
        .hidden_rdata (hidden_rdata)
    );

    // FC Controller
    fc_controller #(
        .RX_NUM          (RX_NUM),
        .WORDS_PER_RX    (WORDS_PER_RX),
        .FC1_OUT_NUM     (FC1_OUT_NUM),
        .FC2_OUT_NUM     (FC2_OUT_NUM),
        .FC3_OUT_NUM     (FC3_OUT_NUM),
        .FC23_GROUPS     (16),
        .FLAT_WORDS      (FLAT_WORDS),
        .FLAT_ADDR_WIDTH (FLAT_ADDR_WIDTH)
    ) u_fc_controller (
        .clk              (clk),
        .rst_n            (rst_n),
        .fc_start         (fc_start),
        .fc_sel           (fc_sel),
        .layer_store_done (layer_store_done),
        .fc_done          (fc_done),
        .active_fc_sel    (active_fc_sel),
        .fifo_empty       (fc1_fifo_empty),
        .fifo_rdata       (fifo_rdata),
        .fifo_re          (fifo_re),
        .fc1_weight_data  (fc1_weight_data),
        .flat_raddr       (flat_raddr),
        .hidden_raddr     (hidden_raddr_ctrl),
        .fcw_raddr        (fcw_raddr),
        .mac_valid        (mac_valid),
        .mac_first        (mac_first),
        .mac_last         (mac_last),
        .mac_tag          (mac_tag)
    );

    // MAC Input MUX
    wire [63:0] mac_act_data;
    wire [63:0] mac_weight_data;

    assign mac_act_data    = (active_fc_sel == FC1) ? flat_rdata : hidden_rdata;
    assign mac_weight_data = (active_fc_sel == FC1) ? fc1_weight_data : fcw_rdata;

    // FC MAC
    wire [31:0] mac_acc;
    wire        acc_valid;
    wire [8:0]  acc_tag;

    fc_mac #(
        .ACC_WIDTH (32),
        .TAG_WIDTH (9)
    ) u_fc_mac (
        .clk         (clk),
        .rst_n       (rst_n),
        .act_data    (mac_act_data),
        .weight_data (mac_weight_data),
        .mac_valid   (mac_valid),
        .mac_first   (mac_first),
        .mac_last    (mac_last),
        .mac_tag     (mac_tag),
        .acc         (mac_acc),
        .acc_valid   (acc_valid),
        .acc_tag     (acc_tag)
    );

    // Requant Parameter Address
    always @(*) begin
        case (acc_tag[8:7])
            FC1: fc_param_raddr = FC1_PARAM_BASE + acc_tag[6:0];
            FC2: fc_param_raddr = FC2_PARAM_BASE + acc_tag[6:0];
            FC3: fc_param_raddr = FC3_PARAM_BASE + acc_tag[6:0];
            default: fc_param_raddr = 9'd0;
        endcase
    end

    // Requant
    wire [7:0] rq;
    wire       rq_valid;
    wire [8:0] rq_tag;

    requant_core #(
        .TAG_WIDTH (9)
    ) u_requant (
        .clk         (clk),
        .rst_n       (rst_n),
        .acc         (mac_acc),
        .acc_valid   (acc_valid),
        .acc_tag     (acc_tag),
        .param_rdata (fc_param_rdata),
        .rq          (rq),
        .rq_valid    (rq_valid),
        .rq_tag      (rq_tag)
    );

    // GELU
    wire [1:0] gelu_table_sel;
    wire       gelu_in_valid;
    wire [7:0] gelu_q;
    wire       gelu_valid;
    wire [8:0] gelu_tag;

    assign gelu_table_sel = (rq_tag[8:7] == FC1) ? 2'b10 : 2'b11;
    assign gelu_in_valid  = rq_valid &&
                            ((rq_tag[8:7] == FC1) || (rq_tag[8:7] == FC2));

    gelu_core #(
        .TAG_WIDTH (9)
    ) u_gelu (
        .clk        (clk),
        .rst_n      (rst_n),
        .rq         (rq),
        .rq_valid   (gelu_in_valid),
        .rq_tag     (rq_tag),
        .table_sel  (gelu_table_sel),
        .lut_raddr  (fc_lut_raddr),
        .lut_rdata  (fc_lut_rdata),
        .gelu_q     (gelu_q),
        .gelu_valid (gelu_valid),
        .gelu_tag   (gelu_tag)
    );

    // Hidden RAM Write
    assign hidden_we = gelu_valid &&
                       ((gelu_tag[8:7] == FC1) || (gelu_tag[8:7] == FC2));
    assign hidden_wbank = (gelu_tag[8:7] == FC2);
    assign hidden_waddr = gelu_tag[6:0];
    assign hidden_wdata = gelu_q;

    // Pose Buffer Write
    wire       pose_we;
    wire [4:0] pose_waddr;
    wire [7:0] pose_wdata;

    assign pose_we    = rq_valid && (rq_tag[8:7] == FC3);
    assign pose_waddr = rq_tag[4:0];
    assign pose_wdata = rq;

    pose_buffer #(
        .DATA_WIDTH (8),
        .DEPTH      (24),
        .ADDR_WIDTH (5)
    ) u_pose_buffer (
        .clk        (clk),
        .rst_n      (rst_n),
        .pose_we    (pose_we),
        .pose_waddr (pose_waddr),
        .pose_wdata (pose_wdata),
        .pose_raddr (pose_raddr),
        .pose_rdata (pose_rdata)
    );

    // Layer Store Done
    wire hidden_store_done;
    wire pose_store_done;

    assign hidden_store_done =
        hidden_we &&
        (((gelu_tag[8:7] == FC1) && (hidden_waddr == FC1_OUT_NUM - 1)) ||
         ((gelu_tag[8:7] == FC2) && (hidden_waddr == FC2_OUT_NUM - 1)));

    assign pose_store_done =
        pose_we && (pose_waddr == FC3_OUT_NUM - 1);

    assign layer_store_done = hidden_store_done || pose_store_done;

endmodule
