`timescale 1 ns / 1 ps

module pose_cnn_v1_0 #(
    // Users to add parameters here
    // Number of receivers. Every RX-dependent block is sized from this value.
    parameter integer RX = 5,
    // User parameters ends
    // Do not modify the parameters beyond this line


    // Parameters of Axi Slave Bus Interface S00_AXI
    parameter integer C_S00_AXI_DATA_WIDTH = 32,
    parameter integer C_S00_AXI_ADDR_WIDTH = 5,

    // Parameters of Axi Master Bus Interface M00_AXI
    parameter C_M00_AXI_TARGET_SLAVE_BASE_ADDR = 32'h00000000,
    parameter integer C_M00_AXI_BURST_LEN = 16,
    parameter integer C_M00_AXI_ID_WIDTH = 1,
    parameter integer C_M00_AXI_ADDR_WIDTH = 32,
    parameter integer C_M00_AXI_DATA_WIDTH = 64
) (
    // Users to add ports here

    // User ports ends
    // Do not modify the ports beyond this line


    // Ports of Axi Slave Bus Interface S00_AXI
    input wire s00_axi_aclk,
    input wire s00_axi_aresetn,
    input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr,
    input wire [2 : 0] s00_axi_awprot,
    input wire s00_axi_awvalid,
    output wire s00_axi_awready,
    input wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata,
    input wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb,
    input wire s00_axi_wvalid,
    output wire s00_axi_wready,
    output wire [1 : 0] s00_axi_bresp,
    output wire s00_axi_bvalid,
    input wire s00_axi_bready,
    input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr,
    input wire [2 : 0] s00_axi_arprot,
    input wire s00_axi_arvalid,
    output wire s00_axi_arready,
    output wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata,
    output wire [1 : 0] s00_axi_rresp,
    output wire s00_axi_rvalid,
    input wire s00_axi_rready,

    // Ports of Axi Master Bus Interface M00_AXI
    input wire m00_axi_aclk,
    input wire m00_axi_aresetn,
    output wire [C_M00_AXI_ID_WIDTH-1 : 0] m00_axi_awid,
    output wire [C_M00_AXI_ADDR_WIDTH-1 : 0] m00_axi_awaddr,
    output wire [7 : 0] m00_axi_awlen,
    output wire [2 : 0] m00_axi_awsize,
    output wire [1 : 0] m00_axi_awburst,
    output wire m00_axi_awlock,
    output wire [3 : 0] m00_axi_awcache,
    output wire [2 : 0] m00_axi_awprot,
    output wire [3 : 0] m00_axi_awqos,
    output wire m00_axi_awvalid,
    input wire m00_axi_awready,
    output wire [C_M00_AXI_DATA_WIDTH-1 : 0] m00_axi_wdata,
    output wire [C_M00_AXI_DATA_WIDTH/8-1 : 0] m00_axi_wstrb,
    output wire m00_axi_wlast,
    output wire m00_axi_wvalid,
    input wire m00_axi_wready,
    input wire [C_M00_AXI_ID_WIDTH-1 : 0] m00_axi_bid,
    input wire [1 : 0] m00_axi_bresp,
    input wire m00_axi_bvalid,
    output wire m00_axi_bready,
    output wire [C_M00_AXI_ID_WIDTH-1 : 0] m00_axi_arid,
    output wire [C_M00_AXI_ADDR_WIDTH-1 : 0] m00_axi_araddr,
    output wire [7 : 0] m00_axi_arlen,
    output wire [2 : 0] m00_axi_arsize,
    output wire [1 : 0] m00_axi_arburst,
    output wire m00_axi_arlock,
    output wire [3 : 0] m00_axi_arcache,
    output wire [2 : 0] m00_axi_arprot,
    output wire [3 : 0] m00_axi_arqos,
    output wire m00_axi_arvalid,
    input wire m00_axi_arready,
    input wire [C_M00_AXI_ID_WIDTH-1 : 0] m00_axi_rid,
    input wire [C_M00_AXI_DATA_WIDTH-1 : 0] m00_axi_rdata,
    input wire [1 : 0] m00_axi_rresp,
    input wire m00_axi_rlast,
    input wire m00_axi_rvalid,
    output wire m00_axi_rready
);
    // CSR 선 (S00_AXI <-> U_POSE_CNN)
    wire        reg_start;
    wire        reg_clear_status;
    wire [31:0] reg_cmd;
    wire [31:0] reg_input_addr;
    wire [31:0] reg_weight_addr;
    wire [31:0] reg_output_addr;
    wire        status_busy;
    wire        status_done;
    wire [ 3:0] status_error;
    wire        cfg_ok;
    wire [31:0] output_scale_bits;

    // MEM 선 (U_POSE_CNN <-> M00_AXI)
    wire        mem_rd_start;
    wire [31:0] mem_rd_addr;
    wire [19:0] mem_rd_bytes;
    wire        mem_rd_busy;
    wire [63:0] mem_rd_data;
    wire        mem_rd_valid;
    wire        mem_rd_ready;
    wire        mem_rd_err;
    wire        mem_wr_start;
    wire [31:0] mem_wr_addr;
    wire [19:0] mem_wr_bytes;
    wire        mem_wr_busy;
    wire [63:0] mem_wr_data;
    wire        mem_wr_ready;
    wire        mem_wr_err;

    // Instantiation of Axi Bus Interface S00_AXI
    pose_cnn_v1_0_S00_AXI #(
        .C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH)
    ) pose_cnn_v1_0_S00_AXI_inst (
        .reg_start        (reg_start),
        .reg_clear_status (reg_clear_status),
        .reg_cmd          (reg_cmd),
        .reg_input_addr   (reg_input_addr),
        .reg_weight_addr  (reg_weight_addr),
        .reg_output_addr  (reg_output_addr),
        .status_busy      (status_busy),
        .status_done      (status_done),
        .status_error     (status_error),
        .cfg_ok           (cfg_ok),
        .output_scale_bits(output_scale_bits),
        .S_AXI_ACLK(s00_axi_aclk),
        .S_AXI_ARESETN(s00_axi_aresetn),
        .S_AXI_AWADDR(s00_axi_awaddr),
        .S_AXI_AWPROT(s00_axi_awprot),
        .S_AXI_AWVALID(s00_axi_awvalid),
        .S_AXI_AWREADY(s00_axi_awready),
        .S_AXI_WDATA(s00_axi_wdata),
        .S_AXI_WSTRB(s00_axi_wstrb),
        .S_AXI_WVALID(s00_axi_wvalid),
        .S_AXI_WREADY(s00_axi_wready),
        .S_AXI_BRESP(s00_axi_bresp),
        .S_AXI_BVALID(s00_axi_bvalid),
        .S_AXI_BREADY(s00_axi_bready),
        .S_AXI_ARADDR(s00_axi_araddr),
        .S_AXI_ARPROT(s00_axi_arprot),
        .S_AXI_ARVALID(s00_axi_arvalid),
        .S_AXI_ARREADY(s00_axi_arready),
        .S_AXI_RDATA(s00_axi_rdata),
        .S_AXI_RRESP(s00_axi_rresp),
        .S_AXI_RVALID(s00_axi_rvalid),
        .S_AXI_RREADY(s00_axi_rready)
    );

    // Instantiation of Axi Bus Interface M00_AXI
    // (m00_axi_aclk/aresetn 포트는 템플릿대로 두고, 내부는 s00 클록 하나로 동작)
    pose_cnn_v1_0_M00_AXI #(
        .C_M_TARGET_SLAVE_BASE_ADDR(C_M00_AXI_TARGET_SLAVE_BASE_ADDR),
        .C_M_AXI_BURST_LEN(C_M00_AXI_BURST_LEN),
        .C_M_AXI_ID_WIDTH(C_M00_AXI_ID_WIDTH),
        .C_M_AXI_ADDR_WIDTH(C_M00_AXI_ADDR_WIDTH),
        .C_M_AXI_DATA_WIDTH(C_M00_AXI_DATA_WIDTH)
    ) pose_cnn_v1_0_M00_AXI_inst (
        .mem_rd_start(mem_rd_start),
        .mem_rd_addr (mem_rd_addr),
        .mem_rd_bytes(mem_rd_bytes),
        .mem_rd_busy (mem_rd_busy),
        .mem_rd_data (mem_rd_data),
        .mem_rd_valid(mem_rd_valid),
        .mem_rd_ready(mem_rd_ready),
        .mem_rd_err  (mem_rd_err),
        .mem_wr_start(mem_wr_start),
        .mem_wr_addr (mem_wr_addr),
        .mem_wr_bytes(mem_wr_bytes),
        .mem_wr_busy (mem_wr_busy),
        .mem_wr_data (mem_wr_data),
        .mem_wr_ready(mem_wr_ready),
        .mem_wr_err  (mem_wr_err),
        .M_AXI_ACLK(s00_axi_aclk),
        .M_AXI_ARESETN(s00_axi_aresetn),
        .M_AXI_AWID(m00_axi_awid),
        .M_AXI_AWADDR(m00_axi_awaddr),
        .M_AXI_AWLEN(m00_axi_awlen),
        .M_AXI_AWSIZE(m00_axi_awsize),
        .M_AXI_AWBURST(m00_axi_awburst),
        .M_AXI_AWLOCK(m00_axi_awlock),
        .M_AXI_AWCACHE(m00_axi_awcache),
        .M_AXI_AWPROT(m00_axi_awprot),
        .M_AXI_AWQOS(m00_axi_awqos),
        .M_AXI_AWVALID(m00_axi_awvalid),
        .M_AXI_AWREADY(m00_axi_awready),
        .M_AXI_WDATA(m00_axi_wdata),
        .M_AXI_WSTRB(m00_axi_wstrb),
        .M_AXI_WLAST(m00_axi_wlast),
        .M_AXI_WVALID(m00_axi_wvalid),
        .M_AXI_WREADY(m00_axi_wready),
        .M_AXI_BID(m00_axi_bid),
        .M_AXI_BRESP(m00_axi_bresp),
        .M_AXI_BVALID(m00_axi_bvalid),
        .M_AXI_BREADY(m00_axi_bready),
        .M_AXI_ARID(m00_axi_arid),
        .M_AXI_ARADDR(m00_axi_araddr),
        .M_AXI_ARLEN(m00_axi_arlen),
        .M_AXI_ARSIZE(m00_axi_arsize),
        .M_AXI_ARBURST(m00_axi_arburst),
        .M_AXI_ARLOCK(m00_axi_arlock),
        .M_AXI_ARCACHE(m00_axi_arcache),
        .M_AXI_ARPROT(m00_axi_arprot),
        .M_AXI_ARQOS(m00_axi_arqos),
        .M_AXI_ARVALID(m00_axi_arvalid),
        .M_AXI_ARREADY(m00_axi_arready),
        .M_AXI_RID(m00_axi_rid),
        .M_AXI_RDATA(m00_axi_rdata),
        .M_AXI_RRESP(m00_axi_rresp),
        .M_AXI_RLAST(m00_axi_rlast),
        .M_AXI_RVALID(m00_axi_rvalid),
        .M_AXI_RREADY(m00_axi_rready)
    );

    // Add user logic here

    // Core reset: two registers between the PS reset block and the core, so the
    // large core reset tree is driven locally (the S00/M00 AXI logic keeps the
    // direct s00_axi_aresetn). Assertion and release both lag by two cycles.
    reg core_rst_n_q1, core_rst_n_q2;
    always @(posedge s00_axi_aclk) begin
        core_rst_n_q1 <= s00_axi_aresetn;
        core_rst_n_q2 <= core_rst_n_q1;
    end

    pose_cnn #(
        .RX(RX)
    ) U_POSE_CNN (
        .clk              (s00_axi_aclk),
        .rst_n            (core_rst_n_q2),
        .reg_start        (reg_start),
        .reg_clear_status (reg_clear_status),
        .reg_cmd          (reg_cmd),
        .reg_input_addr   (reg_input_addr),
        .reg_weight_addr  (reg_weight_addr),
        .reg_output_addr  (reg_output_addr),
        .status_busy      (status_busy),
        .status_done      (status_done),
        .status_error     (status_error),
        .cfg_ok           (cfg_ok),
        .output_scale_bits(output_scale_bits),
        .mem_rd_start     (mem_rd_start),
        .mem_rd_addr      (mem_rd_addr),
        .mem_rd_bytes     (mem_rd_bytes),
        .mem_rd_busy      (mem_rd_busy),
        .mem_rd_data      (mem_rd_data),
        .mem_rd_valid     (mem_rd_valid),
        .mem_rd_ready     (mem_rd_ready),
        .mem_rd_err       (mem_rd_err),
        .mem_wr_start     (mem_wr_start),
        .mem_wr_addr      (mem_wr_addr),
        .mem_wr_bytes     (mem_wr_bytes),
        .mem_wr_busy      (mem_wr_busy),
        .mem_wr_data      (mem_wr_data),
        .mem_wr_ready     (mem_wr_ready),
        .mem_wr_err       (mem_wr_err)
    );

    // User logic ends

endmodule
