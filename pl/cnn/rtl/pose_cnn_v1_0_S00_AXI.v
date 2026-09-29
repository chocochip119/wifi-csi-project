`timescale 1 ns / 1 ps

// S00-05: CSR functionality complete for PROJECT_CONTEXT.md section 5.1.
// Independent AW/W capture, byte-writable CSRs, and read snapshots.
// Registered control pulses and commit-time busy/alignment/BRESP decisions.
// Top owns busy/done/error; system integration and synthesis are separate work.
// This is directly designed RTL, not a copied Xilinx channel implementation.
// Supported project configuration: DATA_WIDTH=32, ADDR_WIDTH=5.
module pose_cnn_v1_0_S00_AXI #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 5
) (
    output wire        reg_start,
    output wire        reg_clear_status,
    output wire [31:0] reg_cmd,
    output wire [31:0] reg_input_addr,
    output wire [31:0] reg_weight_addr,
    output wire [31:0] reg_output_addr,
    output wire [2:0]  reg_rx_count,
    input  wire        status_busy,
    input  wire        status_done,
    input  wire [3:0]  status_error,
    input  wire        cfg_ok,
    input  wire [31:0] output_scale_bits,

    input  wire                                S_AXI_ACLK,
    input  wire                                S_AXI_ARESETN,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]         S_AXI_AWADDR,
    input  wire [2:0]                           S_AXI_AWPROT,
    input  wire                                S_AXI_AWVALID,
    output reg                                 S_AXI_AWREADY,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]         S_AXI_WDATA,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0]     S_AXI_WSTRB,
    input  wire                                S_AXI_WVALID,
    output reg                                 S_AXI_WREADY,
    output wire [1:0]                          S_AXI_BRESP,
    output reg                                 S_AXI_BVALID,
    input  wire                                S_AXI_BREADY,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]         S_AXI_ARADDR,
    input  wire [2:0]                           S_AXI_ARPROT,
    input  wire                                S_AXI_ARVALID,
    output wire                                S_AXI_ARREADY,
    output wire [C_S_AXI_DATA_WIDTH-1:0]         S_AXI_RDATA,
    output wire [1:0]                          S_AXI_RRESP,
    output wire                                S_AXI_RVALID,
    input  wire                                S_AXI_RREADY
);
    localparam [1:0] WR_COLLECT = 2'b00;
    localparam [1:0] WR_RESP    = 2'b01;
    localparam [2:0] SEL_CONTROL     = 3'd0; // 0x00
    localparam [2:0] SEL_STATUS      = 3'd1; // 0x04
    localparam [2:0] SEL_COMMAND     = 3'd2; // 0x08
    localparam [2:0] SEL_INPUT_ADDR  = 3'd3; // 0x0C
    localparam [2:0] SEL_WEIGHT_ADDR = 3'd4; // 0x10
    localparam [2:0] SEL_OUTPUT_ADDR = 3'd5; // 0x14
    localparam [2:0] SEL_SCALE       = 3'd6; // 0x18
    localparam [2:0] SEL_RX_COUNT    = 3'd7; // 0x1C

    reg [1:0] wr_state_reg, wr_state_next;
    reg       channel_enable_reg, channel_enable_next;
    reg       aw_hold_reg, aw_hold_next;
    reg       w_hold_reg, w_hold_next;
    reg [C_S_AXI_ADDR_WIDTH-1:0]     awaddr_reg, awaddr_next;
    reg [C_S_AXI_DATA_WIDTH-1:0]     wdata_reg, wdata_next;
    reg [(C_S_AXI_DATA_WIDTH/8)-1:0] wstrb_reg, wstrb_next;

    reg [31:0] cmd_reg, cmd_next;
    reg [31:0] input_addr_reg, input_addr_next;
    reg [31:0] weight_addr_reg, weight_addr_next;
    reg [31:0] output_addr_reg, output_addr_next;
    reg [2:0]  rx_count_reg, rx_count_next;
    // Combinational selection/merge values; these are not storage registers.
    reg [31:0] csr_cur, csr_merged;
    wire [2:0] wr_sel;
    wire       wr_start_req, wr_clear_req, wr_align_bad;
    reg        wr_reject;
    reg [1:0]  bresp_reg, bresp_next;
    reg        start_reg, start_next;
    reg        clear_status_reg, clear_status_next;

    // One pending read response. Payload is unsigned and sampled at AR acceptance.
    reg        rvalid_reg, rvalid_next;
    reg [31:0] rdata_reg, rdata_next;
    reg [1:0]  rresp_reg, rresp_next;
    reg [31:0] read_data_mux;
    reg [1:0]  read_resp_mux;

    // Internal observation only. A high value at a rising edge is one commit;
    // awaddr_reg/wdata_reg/wstrb_reg hold that transaction's unsigned payload.
    reg commit_valid;

    // Decode held payload, independently of commit. Alignment examines the
    // merged candidate, not unselected WDATA bytes or the CSR access address.
    assign wr_sel       = awaddr_reg[4:2];
    assign wr_start_req = wstrb_reg[0] && wdata_reg[0];
    assign wr_clear_req = wstrb_reg[0] && wdata_reg[1];
    assign wr_align_bad = ((wr_sel == SEL_INPUT_ADDR)  && (csr_merged[2:0] != 3'b0))
                       || ((wr_sel == SEL_WEIGHT_ADDR) && (csr_merged[2:0] != 3'b0))
                       || ((wr_sel == SEL_OUTPUT_ADDR) && (csr_merged[4:0] != 5'b0));
    assign S_AXI_BRESP = bresp_reg;

    // No replacement AR on the R handshake edge: current rvalid still occupies it.
    assign S_AXI_ARREADY = S_AXI_ARESETN && channel_enable_reg && !rvalid_reg;
    // PROJECT_CONTEXT 5.2 AXI clause: keep VALID zero throughout reset.
    assign S_AXI_RVALID  = S_AXI_ARESETN && rvalid_reg;
    assign S_AXI_RDATA   = rdata_reg;
    assign S_AXI_RRESP   = rresp_reg;

    // Registered one-cycle pulses; only AWPROT/ARPROT are unused.
    assign reg_start        = start_reg;
    assign reg_clear_status = clear_status_reg;
    assign reg_cmd          = cmd_reg;
    assign reg_input_addr   = input_addr_reg;
    assign reg_weight_addr  = weight_addr_reg;
    assign reg_output_addr  = output_addr_reg;
    assign reg_rx_count     = rx_count_reg;

    // Synchronous active-low reset; sample low on a rising clock edge.
    // channel_enable is a one-clock startup guard, NOT a reset synchronizer:
    // READY stays low after release until the first rising edge with reset=1.
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            wr_state_reg       <= WR_COLLECT;
            channel_enable_reg <= 1'b0;
            aw_hold_reg        <= 1'b0;
            w_hold_reg         <= 1'b0;
            awaddr_reg         <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            wdata_reg          <= {C_S_AXI_DATA_WIDTH{1'b0}};
            wstrb_reg          <= {(C_S_AXI_DATA_WIDTH/8){1'b0}};
            cmd_reg            <= 32'b0;
            input_addr_reg     <= 32'b0;
            weight_addr_reg    <= 32'b0;
            output_addr_reg    <= 32'b0;
            rx_count_reg       <= 3'd3;
            bresp_reg          <= 2'b00;
            start_reg          <= 1'b0;
            clear_status_reg   <= 1'b0;
        end else begin
            wr_state_reg       <= wr_state_next;
            channel_enable_reg <= channel_enable_next;
            aw_hold_reg        <= aw_hold_next;
            w_hold_reg         <= w_hold_next;
            awaddr_reg         <= awaddr_next;
            wdata_reg          <= wdata_next;
            wstrb_reg          <= wstrb_next;
            cmd_reg            <= cmd_next;
            input_addr_reg     <= input_addr_next;
            weight_addr_reg    <= weight_addr_next;
            output_addr_reg    <= output_addr_next;
            rx_count_reg       <= rx_count_next;
            bresp_reg          <= bresp_next;
            start_reg          <= start_next;
            clear_status_reg   <= clear_status_next;
        end
    end

    always @(*) begin
        wr_state_next       = wr_state_reg;
        channel_enable_next = channel_enable_reg;
        aw_hold_next        = aw_hold_reg;
        w_hold_next         = w_hold_reg;
        awaddr_next         = awaddr_reg;
        wdata_next          = wdata_reg;
        wstrb_next          = wstrb_reg;

        S_AXI_AWREADY = 1'b0;
        S_AXI_WREADY  = 1'b0;
        S_AXI_BVALID  = 1'b0;
        commit_valid = 1'b0;

        channel_enable_next = 1'b1;
        if (S_AXI_ARESETN && channel_enable_reg) begin
            case (wr_state_reg)
                WR_COLLECT: begin
                    S_AXI_AWREADY = !aw_hold_reg;
                    S_AXI_WREADY  = !w_hold_reg;

                    if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                        awaddr_next  = S_AXI_AWADDR;
                        aw_hold_next = 1'b1;
                    end
                    if (S_AXI_WVALID && S_AXI_WREADY) begin
                        wdata_next  = S_AXI_WDATA;
                        wstrb_next  = S_AXI_WSTRB;
                        w_hold_next = 1'b1;
                    end

                    // Use current holds: never commit the just-arriving input.
                    // Consume both entries once, then wait for the B handshake.
                    if (aw_hold_reg && w_hold_reg) begin
                        commit_valid  = 1'b1;
                        aw_hold_next  = 1'b0;
                        w_hold_next   = 1'b0;
                        wr_state_next = WR_RESP;
                    end
                end
                WR_RESP: begin
                    S_AXI_BVALID = 1'b1;
                    // READY outputs stay zero even on this B handshake edge.
                    if (S_AXI_BVALID && S_AXI_BREADY) begin
                        wr_state_next = WR_COLLECT;
                    end
                end
                default: begin
                    // Illegal state: discard holds and recover without commit.
                    wr_state_next = WR_COLLECT;
                    aw_hold_next  = 1'b0;
                    w_hold_next   = 1'b0;
                end
            endcase
        end
    end

    always @(*) begin
        csr_cur          = 32'b0;
        csr_merged       = 32'b0;

        // 1) Select the current value by word offset.
        // D04 confirmed (2026-09-24): ignore low two bits (e.g. 0x0C/0x0E).
        case (wr_sel)
            SEL_COMMAND:     csr_cur = cmd_reg;
            SEL_INPUT_ADDR:  csr_cur = input_addr_reg;
            SEL_WEIGHT_ADDR: csr_cur = weight_addr_reg;
            SEL_OUTPUT_ADDR: csr_cur = output_addr_reg;
            SEL_RX_COUNT:    csr_cur = {29'b0, rx_count_reg};
            default:         csr_cur = 32'b0;
        endcase

        // 2) Merge selected bytes once. WSTRB=0 naturally preserves csr_cur.
        csr_merged = csr_cur;
        if (wstrb_reg[0]) csr_merged[7:0]   = wdata_reg[7:0];
        if (wstrb_reg[1]) csr_merged[15:8]  = wdata_reg[15:8];
        if (wstrb_reg[2]) csr_merged[23:16] = wdata_reg[23:16];
        if (wstrb_reg[3]) csr_merged[31:24] = wdata_reg[31:24];

    end

    // Pure decision logic: no dependency on commit_valid or FSM next values.
    always @(*) begin
        wr_reject = 1'b0;
        case (wr_sel)
            SEL_STATUS, SEL_SCALE: begin
                // 1) RO/reserved writes: OKAY regardless of busy or WSTRB.
                wr_reject = 1'b0;
            end
            SEL_CONTROL: begin
                // 2) Busy START rejects the entire CONTROL write (including CLEAR).
                // 3) Otherwise allow strobed pulses; reserved bits are ignored.
                wr_reject = wr_start_req && status_busy;
            end
            SEL_COMMAND, SEL_INPUT_ADDR, SEL_WEIGHT_ADDR, SEL_OUTPUT_ADDR: begin
                if (status_busy) begin
                    // 4) Busy RW writes reject even when WSTRB=0.
                    wr_reject = 1'b1;
                end else begin
                    // 5) Idle RW writes check the merged DDR address candidate.
                    // COMMAND is excluded by wr_align_bad's address selection.
                    wr_reject = wr_align_bad;
                end
            end
            SEL_RX_COUNT: begin
                // RX_COUNT is an RW CSR. Only the supported 1..7 range commits.
                if (status_busy)
                    wr_reject = 1'b1;
                else
                    wr_reject = (csr_merged < 32'd1) || (csr_merged > 32'd7);
            end
            default: wr_reject = 1'b0;
        endcase
    end

    always @(*) begin
        cmd_next          = cmd_reg;
        input_addr_next   = input_addr_reg;
        weight_addr_next  = weight_addr_reg;
        output_addr_next  = output_addr_reg;
        rx_count_next     = rx_count_reg;
        bresp_next        = bresp_reg;
        start_next        = 1'b0;
        clear_status_next = 1'b0;

        // 3) Snapshot the decision at commit. B stalls never re-evaluate it.
        // Pulse defaults are zero, so each accepted request lasts one cycle.
        if (commit_valid) begin
            bresp_next = wr_reject ? 2'b10 : 2'b00;
            if (!wr_reject) begin
                case (wr_sel)
                    SEL_CONTROL: begin
                        start_next        = wr_start_req;
                        clear_status_next = wr_clear_req;
                    end
                    // COMMAND keeps all 32 bits; Top validates it at START.
                    SEL_COMMAND:     cmd_next         = csr_merged;
                    SEL_INPUT_ADDR:  input_addr_next  = csr_merged;
                    SEL_WEIGHT_ADDR: weight_addr_next = csr_merged;
                    SEL_OUTPUT_ADDR: output_addr_next = csr_merged;
                    SEL_RX_COUNT:    rx_count_next     = csr_merged[2:0];
                    default: begin
                        // RO/reserved writes keep all stored values and pulses.
                    end
                endcase
            end
        end
    end

    // Compute all read choices independently of handshake and write state.
    always @(*) begin
        read_data_mux = 32'b0;
        read_resp_mux = 2'b00;

        // D04 confirmed (2026-09-24): ARADDR[1:0] is ignored too.
        case (S_AXI_ARADDR[4:2])
            SEL_CONTROL:     read_data_mux = 32'b0;
            SEL_STATUS:      read_data_mux = {24'b0, status_error[3:0], cfg_ok,
                                             |status_error, status_done, status_busy};
            SEL_COMMAND:     read_data_mux = cmd_reg;
            SEL_INPUT_ADDR:  read_data_mux = input_addr_reg;
            SEL_WEIGHT_ADDR: read_data_mux = weight_addr_reg;
            SEL_OUTPUT_ADDR: read_data_mux = output_addr_reg;
            SEL_RX_COUNT:    read_data_mux = {29'b0, rx_count_reg};
            SEL_SCALE: begin
                read_data_mux = cfg_ok ? output_scale_bits : 32'b0;
                read_resp_mux = cfg_ok ? 2'b00 : 2'b10;
            end
            default: begin
                read_data_mux = 32'b0;
                read_resp_mux = 2'b00;
            end
        endcase
    end

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            rvalid_reg <= 1'b0;
            rdata_reg  <= 32'b0;
            rresp_reg  <= 2'b00;
        end else begin
            rvalid_reg <= rvalid_next;
            rdata_reg  <= rdata_next;
            rresp_reg  <= rresp_next;
        end
    end

    always @(*) begin
        rvalid_next = rvalid_reg;
        rdata_next  = rdata_reg;
        rresp_next  = rresp_reg;

        if (S_AXI_ARESETN && channel_enable_reg) begin
            case (rvalid_reg)
                1'b0: begin
                    if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                        rvalid_next = 1'b1;
                        // Current CSR/status values: simultaneous NBA updates
                        // are visible only to a later read (D03 R4).
                        rdata_next = read_data_mux;
                        rresp_next = read_resp_mux;
                    end
                end
                1'b1: begin
                    // ARVALID and changing live inputs cannot cancel/alter R.
                    if (S_AXI_RVALID && S_AXI_RREADY) rvalid_next = 1'b0;
                end
                default: begin
                    // Recover an invalid simulation state without a response.
                    rvalid_next = 1'b0;
                    rdata_next  = 32'b0;
                    rresp_next  = 2'b00;
                end
            endcase
        end
    end
endmodule
