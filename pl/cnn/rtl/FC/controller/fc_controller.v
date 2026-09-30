`timescale 1ns / 1ps

module fc_controller #(
    parameter integer RX_NUM         = 3,
    parameter integer WORDS_PER_RX   = 128,
    parameter integer FC1_OUT_NUM    = 128,
    parameter integer FC2_OUT_NUM    = 128,
    parameter integer FC3_OUT_NUM    = 24,
    parameter integer FC23_GROUPS    = 16,
    parameter integer FLAT_WORDS     = RX_NUM * WORDS_PER_RX,
    parameter integer FLAT_ADDR_WIDTH =
        (FLAT_WORDS <= 1) ? 1 : $clog2(FLAT_WORDS)
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         fc_start,
    input  wire [1:0]                   fc_sel,
    input  wire                         layer_store_done,
    output reg                          fc_done,
    output wire [1:0]                   active_fc_sel,

    input  wire                         fifo_empty,
    input  wire [63:0]                  fifo_rdata,
    output wire                         fifo_re,
    output reg  [63:0]                  fc1_weight_data,

    output reg  [FLAT_ADDR_WIDTH-1:0]   flat_raddr,
    output reg  [4:0]                   hidden_raddr,
    output reg  [11:0]                  fcw_raddr,

    output reg                          mac_valid,
    output reg                          mac_first,
    output reg                          mac_last,
    output reg  [8:0]                   mac_tag
);
    // Layer Select
    localparam [1:0] FC1 = 2'd0;
    localparam [1:0] FC2 = 2'd1;
    localparam [1:0] FC3 = 2'd2;

    // FSM State
    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_RUN  = 2'd1;
    localparam [1:0] S_WAIT = 2'd2;

    // Weight Address Map
    localparam integer FC2_W_BASE = 0;
    localparam integer FC3_W_BASE = 2048;

    // Counter Width
    localparam integer GROUP_WIDTH =
        (FLAT_WORDS > FC23_GROUPS) ? $clog2(FLAT_WORDS) : $clog2(FC23_GROUPS);

    reg [1:0] state;
    reg [1:0] fc_sel_reg;
    reg [6:0] out_idx;
    reg [GROUP_WIDTH-1:0] group_idx;
    reg [GROUP_WIDTH-1:0] group_last;
    reg [6:0] out_last;

    wire issue_fire;

    assign active_fc_sel = fc_sel_reg;

    // Layer Last Index
    always @(*) begin
        case (fc_sel_reg)
            FC1: begin
                group_last = FLAT_WORDS - 1;
                out_last   = FC1_OUT_NUM - 1;
            end
            FC2: begin
                group_last = FC23_GROUPS - 1;
                out_last   = FC2_OUT_NUM - 1;
            end
            FC3: begin
                group_last = FC23_GROUPS - 1;
                out_last   = FC3_OUT_NUM - 1;
            end
            default: begin
                group_last = 0;
                out_last   = 0;
            end
        endcase
    end

    // Issue Control
    assign issue_fire =
        (state == S_RUN) && ((fc_sel_reg != FC1) || !fifo_empty);

    assign fifo_re = issue_fire && (fc_sel_reg == FC1);

    // Read Address Generation
    always @(*) begin
        flat_raddr   = 0;
        hidden_raddr = 0;
        fcw_raddr    = 0;

        if (state == S_RUN) begin
            case (fc_sel_reg)
                FC1: begin
                    flat_raddr = group_idx[FLAT_ADDR_WIDTH-1:0];
                end
                FC2: begin
                    hidden_raddr = {1'b0, group_idx[3:0]};
                    fcw_raddr = FC2_W_BASE + {out_idx, 4'b0000} + group_idx[3:0];
                end
                FC3: begin
                    hidden_raddr = {1'b1, group_idx[3:0]};
                    fcw_raddr = FC3_W_BASE + {out_idx, 4'b0000} + group_idx[3:0];
                end
                default: begin
                    flat_raddr   = 0;
                    hidden_raddr = 0;
                    fcw_raddr    = 0;
                end
            endcase
        end
    end

    // Main FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= S_IDLE;
            fc_sel_reg      <= FC1;
            out_idx         <= 0;
            group_idx       <= 0;
            fc1_weight_data <= 0;
            mac_valid       <= 0;
            mac_first       <= 0;
            mac_last        <= 0;
            mac_tag         <= 0;
            fc_done         <= 0;
        end else begin
            mac_valid <= 1'b0;
            mac_first <= 1'b0;
            mac_last  <= 1'b0;
            fc_done   <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (fc_start) begin
                        fc_sel_reg <= fc_sel;
                        out_idx    <= 0;
                        group_idx  <= 0;
                        state      <= S_RUN;
                    end
                end

                S_RUN: begin
                    if (issue_fire) begin
                        mac_valid <= 1'b1;
                        mac_first <= (group_idx == 0);
                        mac_last  <= (group_idx == group_last);
                        mac_tag   <= {fc_sel_reg, out_idx};

                        if (fc_sel_reg == FC1)
                            fc1_weight_data <= fifo_rdata;

                        if (group_idx == group_last) begin
                            group_idx <= 0;

                            if (out_idx == out_last) begin
                                state <= S_WAIT;
                            end else begin
                                out_idx <= out_idx + 1'b1;
                            end
                        end else begin
                            group_idx <= group_idx + 1'b1;
                        end
                    end
                end

                S_WAIT: begin
                    if (layer_store_done) begin
                        fc_done <= 1'b1;
                        state   <= S_IDLE;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
