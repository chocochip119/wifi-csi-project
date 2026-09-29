`timescale 1ns / 1ps

// IP_v1_0 MEM interface: 32-bit byte address, 64-bit data, 20-bit byte count.
// One outstanding burst per direction; read and write can run independently.
// Synthesizable Verilog-2001 RTL. SystemVerilog is used only by the testbench.
module pose_cnn_v1_0_M00_AXI #(
    parameter [31:0] C_M_TARGET_SLAVE_BASE_ADDR = 32'h0000_0000,
    parameter integer C_M_AXI_BURST_LEN   = 16,
    parameter integer C_M_AXI_ID_WIDTH    = 1,
    parameter integer C_M_AXI_ADDR_WIDTH  = 32,
    parameter integer C_M_AXI_DATA_WIDTH  = 64,
    // 0 disables the watchdog. Timeout reports an error but NEVER cancels AXI.
    parameter integer WATCHDOG_CYCLES = 0
) (
    input  wire        mem_rd_start,
    input  wire [31:0] mem_rd_addr,
    input  wire [19:0] mem_rd_bytes,
    output wire        mem_rd_busy,
    output wire [63:0] mem_rd_data,
    output wire        mem_rd_valid,
    input  wire        mem_rd_ready,
    output reg         mem_rd_err,
    input  wire        mem_wr_start,
    input  wire [31:0] mem_wr_addr,
    input  wire [19:0] mem_wr_bytes,
    output wire        mem_wr_busy,
    input  wire [63:0] mem_wr_data,
    output wire        mem_wr_ready,
    output reg         mem_wr_err,

    input  wire M_AXI_ACLK,
    input  wire M_AXI_ARESETN,
    output wire [C_M_AXI_ID_WIDTH-1:0] M_AXI_AWID,
    output wire [C_M_AXI_ADDR_WIDTH-1:0] M_AXI_AWADDR,
    output wire [7:0] M_AXI_AWLEN,
    output wire [2:0] M_AXI_AWSIZE,
    output wire [1:0] M_AXI_AWBURST,
    output wire M_AXI_AWLOCK,
    output wire [3:0] M_AXI_AWCACHE,
    output wire [2:0] M_AXI_AWPROT,
    output wire [3:0] M_AXI_AWQOS,
    output wire M_AXI_AWVALID,
    input  wire M_AXI_AWREADY,
    output wire [C_M_AXI_DATA_WIDTH-1:0] M_AXI_WDATA,
    output wire [C_M_AXI_DATA_WIDTH/8-1:0] M_AXI_WSTRB,
    output wire M_AXI_WLAST,
    output wire M_AXI_WVALID,
    input  wire M_AXI_WREADY,
    input  wire [C_M_AXI_ID_WIDTH-1:0] M_AXI_BID,
    input  wire [1:0] M_AXI_BRESP,
    input  wire M_AXI_BVALID,
    output wire M_AXI_BREADY,
    output wire [C_M_AXI_ID_WIDTH-1:0] M_AXI_ARID,
    output wire [C_M_AXI_ADDR_WIDTH-1:0] M_AXI_ARADDR,
    output wire [7:0] M_AXI_ARLEN,
    output wire [2:0] M_AXI_ARSIZE,
    output wire [1:0] M_AXI_ARBURST,
    output wire M_AXI_ARLOCK,
    output wire [3:0] M_AXI_ARCACHE,
    output wire [2:0] M_AXI_ARPROT,
    output wire [3:0] M_AXI_ARQOS,
    output wire M_AXI_ARVALID,
    input  wire M_AXI_ARREADY,
    input  wire [C_M_AXI_ID_WIDTH-1:0] M_AXI_RID,
    input  wire [C_M_AXI_DATA_WIDTH-1:0] M_AXI_RDATA,
    input  wire [1:0] M_AXI_RRESP,
    input  wire M_AXI_RLAST,
    input  wire M_AXI_RVALID,
    output wire M_AXI_RREADY
);
    localparam [2:0] RD_IDLE  = 3'd0;
    localparam [2:0] RD_PLAN  = 3'd1;
    localparam [2:0] RD_ADDR  = 3'd2;
    localparam [2:0] RD_DATA  = 3'd3;
    localparam [2:0] RD_FAULT = 3'd4;

    localparam [2:0] WR_IDLE = 3'd0;
    localparam [2:0] WR_PLAN = 3'd1;
    localparam [2:0] WR_SEND = 3'd2;
    localparam [2:0] WR_RESP = 3'd3;

    reg [2:0] rd_state, rd_state_next;
    reg [2:0] wr_state, wr_state_next;
    reg [31:0] rd_addr_reg, wr_addr_reg;
    reg [19:0] rd_bytes_left, wr_bytes_left;
    reg [4:0] rd_burst_beats, wr_burst_beats;
    reg [4:0] rd_beat_count, wr_beat_count;
    reg wr_aw_sent;
    reg [31:0] rd_wait_count, wr_wait_count;

    wire rd_fire, wr_fire, aw_fire, b_fire;
    wire rd_last_expected;
    wire rd_waiting, wr_waiting;

    // Addresses are absolute DDR addresses. BASE_ADDR is retained for wrapper
    // compatibility, intentionally NOT added (as required by the IP spec).
    function invalid_command;
        input [31:0] addr;
        input [19:0] bytes;
        reg [32:0] end_exclusive;
        begin
            end_exclusive = {1'b0, addr} + {13'b0, bytes};
            invalid_command = (bytes == 0) || (addr[2:0] != 0) ||
                              (bytes[2:0] != 0) ||
                              (end_exclusive > 33'h1_0000_0000);
        end
    endfunction

    function [4:0] burst_beats;
        input [31:0] addr;
        input [19:0] bytes;
        integer beats;
        integer boundary_beats;
        begin
            beats = bytes >> 3;
            boundary_beats = (4096 - {20'b0, addr[11:0]}) >> 3;
            if (beats > C_M_AXI_BURST_LEN)
                beats = C_M_AXI_BURST_LEN;
            if (beats > boundary_beats)
                beats = boundary_beats;
            burst_beats = beats[4:0];
        end
    endfunction

    assign M_AXI_AWID    = {C_M_AXI_ID_WIDTH{1'b0}};
    assign M_AXI_AWSIZE  = 3'd3;
    assign M_AXI_AWBURST = 2'b01;
    assign M_AXI_AWLOCK  = 1'b0;
    assign M_AXI_AWCACHE = 4'b0011;
    assign M_AXI_AWPROT  = 3'b000;
    assign M_AXI_AWQOS   = 4'b0000;
    assign M_AXI_ARID    = {C_M_AXI_ID_WIDTH{1'b0}};
    assign M_AXI_ARSIZE  = 3'd3;
    assign M_AXI_ARBURST = 2'b01;
    assign M_AXI_ARLOCK  = 1'b0;
    assign M_AXI_ARCACHE = 4'b0011;
    assign M_AXI_ARPROT  = 3'b000;
    assign M_AXI_ARQOS   = 4'b0000;

    assign mem_rd_busy   = (rd_state != RD_IDLE);
    assign M_AXI_ARADDR  = rd_addr_reg;
    assign M_AXI_ARLEN   = {3'b000, rd_burst_beats} - 8'd1;
    assign M_AXI_ARVALID = (rd_state == RD_ADDR);
    assign mem_rd_data   = M_AXI_RDATA;
    assign mem_rd_valid  = (rd_state == RD_DATA) && M_AXI_RVALID;
    assign M_AXI_RREADY  = (rd_state == RD_DATA) && mem_rd_ready;
    assign rd_fire       = M_AXI_RVALID && M_AXI_RREADY;
    assign rd_last_expected = (rd_beat_count == rd_burst_beats - 1'b1);

    assign mem_wr_busy   = (wr_state != WR_IDLE);
    assign M_AXI_AWADDR  = wr_addr_reg;
    assign M_AXI_AWLEN   = {3'b000, wr_burst_beats} - 8'd1;
    // AWVALID and WVALID are independent: do not wait for AWREADY to issue W.
    assign M_AXI_AWVALID = (wr_state == WR_SEND) && !wr_aw_sent;
    assign M_AXI_WVALID  = (wr_state == WR_SEND) &&
                           (wr_beat_count < wr_burst_beats);
    assign M_AXI_WDATA   = mem_wr_data;
    assign M_AXI_WSTRB   = 8'hff;
    assign M_AXI_WLAST   = (wr_beat_count == wr_burst_beats - 1'b1);
    assign M_AXI_BREADY  = (wr_state == WR_RESP);
    assign wr_fire       = M_AXI_WVALID && M_AXI_WREADY;
    assign aw_fire       = M_AXI_AWVALID && M_AXI_AWREADY;
    assign b_fire        = M_AXI_BVALID && M_AXI_BREADY;
    // Producer must hold mem_wr_data until this transfer notification.
    assign mem_wr_ready  = wr_fire;

    // ===== Read state machine =====
    always @(*) begin
        rd_state_next = rd_state;
        case (rd_state)
            RD_IDLE: begin
                if (mem_rd_start)
                    rd_state_next = RD_PLAN;
            end
            RD_PLAN: begin
                if (invalid_command(rd_addr_reg, rd_bytes_left))
                    rd_state_next = RD_IDLE;
                else
                    rd_state_next = RD_ADDR;
            end
            RD_ADDR: begin
                if (M_AXI_ARREADY)
                    rd_state_next = RD_DATA;
            end
            RD_DATA: begin
                if (rd_fire) begin
                    // A malformed RLAST requires a coordinated reset.
                    if (M_AXI_RLAST != rd_last_expected)
                        rd_state_next = RD_FAULT;
                    else if (rd_last_expected) begin
                        if (rd_bytes_left == ({15'b0, rd_burst_beats} << 3))
                            rd_state_next = RD_IDLE;
                        else
                            rd_state_next = RD_PLAN;
                    end
                end
            end
            RD_FAULT: rd_state_next = RD_FAULT;
            default:  rd_state_next = RD_FAULT;
        endcase
    end

    always @(posedge M_AXI_ACLK or negedge M_AXI_ARESETN) begin
        if (!M_AXI_ARESETN) begin
            rd_state       <= RD_IDLE;
            rd_addr_reg    <= 32'd0;
            rd_bytes_left  <= 20'd0;
            rd_burst_beats <= 5'd0;
            rd_beat_count  <= 5'd0;
            mem_rd_err     <= 1'b0;
            rd_wait_count  <= 32'd0;
        end else begin
            rd_state <= rd_state_next;
            if (rd_state == RD_IDLE && mem_rd_start) begin
                rd_addr_reg   <= mem_rd_addr;
                rd_bytes_left <= mem_rd_bytes;
                mem_rd_err    <= 1'b0;
            end
            if (rd_state == RD_PLAN) begin
                rd_burst_beats <= burst_beats(rd_addr_reg, rd_bytes_left);
                rd_beat_count  <= 5'd0;
                if (invalid_command(rd_addr_reg, rd_bytes_left))
                    mem_rd_err <= 1'b1;
            end
            if (rd_fire) begin
                rd_beat_count <= rd_beat_count + 1'b1;
                if ((M_AXI_RRESP != 2'b00) ||
                    (M_AXI_RID != {C_M_AXI_ID_WIDTH{1'b0}}) ||
                    (M_AXI_RLAST != rd_last_expected))
                    mem_rd_err <= 1'b1;
                if (rd_last_expected) begin
                    rd_addr_reg <= rd_addr_reg +
                                   ({27'b0, rd_burst_beats} << 3);
                    rd_bytes_left <= rd_bytes_left -
                                     ({15'b0, rd_burst_beats} << 3);
                end
            end
            if (!rd_waiting || WATCHDOG_CYCLES == 0)
                rd_wait_count <= 32'd0;
            else if (rd_wait_count < WATCHDOG_CYCLES) begin
                rd_wait_count <= rd_wait_count + 1'b1;
                if (rd_wait_count == WATCHDOG_CYCLES - 1)
                    mem_rd_err <= 1'b1;
            end
        end
    end

    // ===== Write state machine =====
    always @(*) begin
        wr_state_next = wr_state;
        case (wr_state)
            WR_IDLE: begin
                if (mem_wr_start)
                    wr_state_next = WR_PLAN;
            end
            WR_PLAN: begin
                if (invalid_command(wr_addr_reg, wr_bytes_left))
                    wr_state_next = WR_IDLE;
                else
                    wr_state_next = WR_SEND;
            end
            WR_SEND: begin
                if ((wr_aw_sent || aw_fire) &&
                    ((wr_beat_count == wr_burst_beats) ||
                     (wr_fire && M_AXI_WLAST)))
                    wr_state_next = WR_RESP;
            end
            WR_RESP: begin
                if (b_fire) begin
                    if (wr_bytes_left == ({15'b0, wr_burst_beats} << 3))
                        wr_state_next = WR_IDLE;
                    else
                        wr_state_next = WR_PLAN;
                end
            end
            default: wr_state_next = WR_IDLE;
        endcase
    end

    always @(posedge M_AXI_ACLK or negedge M_AXI_ARESETN) begin
        if (!M_AXI_ARESETN) begin
            wr_state       <= WR_IDLE;
            wr_addr_reg    <= 32'd0;
            wr_bytes_left  <= 20'd0;
            wr_burst_beats <= 5'd0;
            wr_beat_count  <= 5'd0;
            wr_aw_sent     <= 1'b0;
            mem_wr_err     <= 1'b0;
            wr_wait_count  <= 32'd0;
        end else begin
            wr_state <= wr_state_next;
            if (wr_state == WR_IDLE && mem_wr_start) begin
                wr_addr_reg   <= mem_wr_addr;
                wr_bytes_left <= mem_wr_bytes;
                mem_wr_err    <= 1'b0;
            end
            if (wr_state == WR_PLAN) begin
                wr_burst_beats <= burst_beats(wr_addr_reg, wr_bytes_left);
                wr_beat_count  <= 5'd0;
                wr_aw_sent     <= 1'b0;
                if (invalid_command(wr_addr_reg, wr_bytes_left))
                    mem_wr_err <= 1'b1;
            end
            if (aw_fire)
                wr_aw_sent <= 1'b1;
            if (wr_fire)
                wr_beat_count <= wr_beat_count + 1'b1;
            if (b_fire) begin
                if ((M_AXI_BRESP != 2'b00) ||
                    (M_AXI_BID != {C_M_AXI_ID_WIDTH{1'b0}}))
                    mem_wr_err <= 1'b1;
                wr_addr_reg <= wr_addr_reg +
                               ({27'b0, wr_burst_beats} << 3);
                wr_bytes_left <= wr_bytes_left -
                                 ({15'b0, wr_burst_beats} << 3);
            end
            if (!wr_waiting || WATCHDOG_CYCLES == 0)
                wr_wait_count <= 32'd0;
            else if (wr_wait_count < WATCHDOG_CYCLES) begin
                wr_wait_count <= wr_wait_count + 1'b1;
                if (wr_wait_count == WATCHDOG_CYCLES - 1)
                    mem_wr_err <= 1'b1;
            end
        end
    end

    assign rd_waiting = ((rd_state == RD_ADDR) && !M_AXI_ARREADY) ||
                        ((rd_state == RD_DATA) && mem_rd_ready && !M_AXI_RVALID);
    assign wr_waiting = ((wr_state == WR_SEND) && !aw_fire && !wr_fire) ||
                        ((wr_state == WR_RESP) && !M_AXI_BVALID);
    
    // Synthesis-visible guard for the supported burst length.
    generate
        if ((C_M_AXI_BURST_LEN < 1) ||
            (C_M_AXI_BURST_LEN > 16)) begin : GEN_INVALID_BURST_LEN
            INVALID_C_M_AXI_BURST_LEN invalid_burst_len();
        end
    endgenerate

    // synthesis translate_off
    initial begin
        if ((C_M_AXI_ADDR_WIDTH != 32) ||
            (C_M_AXI_DATA_WIDTH != 64) ||
            (C_M_AXI_ID_WIDTH < 1)) begin
            $display("ERROR: IP_v1_0 requires ADDR=32, DATA=64, ID>=1");
            $finish;
        end
        if ((C_M_AXI_BURST_LEN < 1) ||
            (C_M_AXI_BURST_LEN > 16) ||
            (WATCHDOG_CYCLES < 0)) begin
            $display("ERROR: BURST_LEN must be 1..16 and WATCHDOG_CYCLES >= 0");
            $finish;
        end
    end
    // synthesis translate_on
endmodule
