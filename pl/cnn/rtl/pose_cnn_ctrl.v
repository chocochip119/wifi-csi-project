`timescale 1 ns / 1 ps

// T-07: all thirteen states implemented, including shared read-error drain.
// D08: no local timeout/abort; PS recovery policy is PROJECT_CONTEXT.md 5.4.
// Contract: pose_cnn_ctrl_fsm.drawio p1/p2; PROJECT_CONTEXT.md 5.1 D02/D03, 5.2 reset.
module pose_cnn_ctrl (
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
    input  wire         cfg_ok,

    output reg          mem_rd_start,
    output reg  [31:0]  mem_rd_addr,
    output reg  [19:0]  mem_rd_bytes,
    input  wire         mem_rd_busy,
    input  wire [63:0]  mem_rd_data,
    input  wire         mem_rd_valid,
    output reg          mem_rd_ready,
    input  wire         mem_rd_err,
    output reg          mem_wr_start,
    output reg  [31:0]  mem_wr_addr,
    output reg  [19:0]  mem_wr_bytes,
    input  wire         mem_wr_busy,
    output reg  [63:0]  mem_wr_data,
    input  wire         mem_wr_ready,
    input  wire         mem_wr_err,

    output reg          loader_start,
    input  wire         loader_done,
    input  wire         loader_err,
    output reg  [63:0]  ld_data,
    output reg          ld_valid,
    input  wire         ld_ready,
    // D09 C: explicit read-address ownership for the Loader's shared RAM ports.
    output wire         param_sel_fc,
    output wire         lut_sel_fc,
    // D08: no consumer abort port; recovery uses the verified common reset.

    output reg          enc_start,
    input  wire         enc_done,
    output reg          in_we,
    output reg  [10:0]  in_waddr,
    output reg  [63:0]  in_wdata,
    output reg          fc_start,
    input  wire         fc_done,
    output reg  [1:0]   fc_sel,
    output reg          fifo_we,
    output reg  [63:0]  fifo_wdata,
    input  wire         fifo_full,
    input  wire [191:0] pose_data
);
    // T-00 p1: all thirteen target states retain the diagram's 4-bit encoding.
    localparam [3:0] IDLE      = 4'b0000;
    localparam [3:0] DECODE    = 4'b0001;
    localparam [3:0] LD_RD1    = 4'b0010;
    localparam [3:0] LD_RD2    = 4'b0011;
    localparam [3:0] LD_WAIT   = 4'b0100;
    localparam [3:0] IN_RD     = 4'b0101;
    localparam [3:0] ENC       = 4'b0110;
    localparam [3:0] FC1       = 4'b0111;
    localparam [3:0] FC2       = 4'b1000;
    localparam [3:0] FC3       = 4'b1001;
    localparam [3:0] WR        = 4'b1010;
    localparam [3:0] ERR_DRAIN = 4'b1011;
    localparam [3:0] FINISH    = 4'b1100;
    localparam [31:0] CMD_INFER = 32'd0;
    localparam [31:0] CMD_LOAD  = 32'd1;
    localparam [3:0] ERR_NONE    = 4'd0;
    localparam [3:0] ERR_BAD_CMD = 4'd1;
    localparam [3:0] ERR_NO_CFG  = 4'd2;
    localparam [3:0] ERR_BLOB    = 4'd3;
    localparam [3:0] ERR_MEM_RD  = 4'd4;
    localparam [3:0] ERR_MEM_WR  = 4'd5;

    reg [3:0]  state_reg, state_next;
    // Unsigned configuration snapshots; only reset/accepted START changes them.
    reg [31:0] cmd_reg, cmd_next;
    reg [31:0] input_addr_reg, input_addr_next;
    reg [31:0] weight_addr_reg, weight_addr_next;
    reg [31:0] output_addr_reg, output_addr_next;
    // Internal execution result is separate from the software-visible display.
    reg [3:0]  run_error_reg, run_error_next;
    reg        done_reg, done_next;
    reg [3:0]  error_reg, error_next;
    reg        mem_rd_busy_prev_reg;
    reg        mem_wr_busy_prev_reg;
    reg        loader_done_seen_reg, loader_done_seen_next;
    reg        loader_error_seen_reg, loader_error_seen_next;
    reg [10:0] beat_reg, beat_next;
    reg [31:0] load_base_reg, load_base_next;
    reg [31:0] ld2_addr_reg, ld2_addr_next;
    reg [31:0] fc1_addr_reg, fc1_addr_next;
    reg        fc_done_seen_reg, fc_done_seen_next;

    assign status_busy  = (state_reg != IDLE);
    assign status_done  = done_reg;
    assign status_error = error_reg;
    // Current-state decode, not fc_start: RAM samples the selected address on
    // its next rising edge. No extra register or change to the FSM sequence.
    assign param_sel_fc = (state_reg == FC1) || (state_reg == FC2) || (state_reg == FC3);
    assign lut_sel_fc   = (state_reg == FC1) || (state_reg == FC2) || (state_reg == FC3);

    // User decision (2026-09-25): synchronous active-low reset, as in Encoder.
    always @(posedge clk) begin
        if (!rst_n) begin
            state_reg       <= IDLE;
            cmd_reg         <= 32'b0;
            input_addr_reg  <= 32'b0;
            weight_addr_reg <= 32'b0;
            output_addr_reg <= 32'b0;
            run_error_reg   <= ERR_NONE;
            done_reg        <= 1'b0;
            error_reg       <= ERR_NONE;
            mem_rd_busy_prev_reg <= 1'b0;
            mem_wr_busy_prev_reg <= 1'b0;
            loader_done_seen_reg <= 1'b0;
            loader_error_seen_reg <= 1'b0;
            beat_reg        <= 11'd0;
            load_base_reg   <= 32'd0;
            ld2_addr_reg    <= 32'd0;
            fc1_addr_reg    <= 32'd0;
            fc_done_seen_reg <= 1'b0;
        end else begin
            state_reg       <= state_next;
            cmd_reg         <= cmd_next;
            input_addr_reg  <= input_addr_next;
            weight_addr_reg <= weight_addr_next;
            output_addr_reg <= output_addr_next;
            run_error_reg   <= run_error_next;
            done_reg        <= done_next;
            error_reg       <= error_next;
            mem_rd_busy_prev_reg <= mem_rd_busy;
            mem_wr_busy_prev_reg <= mem_wr_busy;
            loader_done_seen_reg <= loader_done_seen_next;
            loader_error_seen_reg <= loader_error_seen_next;
            beat_reg        <= beat_next;
            load_base_reg   <= load_base_next;
            ld2_addr_reg    <= ld2_addr_next;
            fc1_addr_reg    <= fc1_addr_next;
            fc_done_seen_reg <= fc_done_seen_next;
        end
    end

    always @(*) begin
        state_next       = state_reg;
        cmd_next         = cmd_reg;
        input_addr_next  = input_addr_reg;
        weight_addr_next = weight_addr_reg;
        output_addr_next = output_addr_reg;
        run_error_next   = run_error_reg;
        done_next        = done_reg;
        error_next       = error_reg;
        loader_done_seen_next = loader_done_seen_reg;
        loader_error_seen_next = loader_error_seen_reg;
        beat_next        = beat_reg;
        load_base_next   = load_base_reg;
        ld2_addr_next    = ld2_addr_reg;
        fc1_addr_next    = fc1_addr_reg;
        fc_done_seen_next = fc_done_seen_reg;
        mem_rd_start     = 1'b0;
        mem_rd_addr      = 32'b0;
        mem_rd_bytes     = 20'b0;
        mem_rd_ready     = 1'b0;
        mem_wr_start     = 1'b0;
        mem_wr_addr      = 32'd0;
        mem_wr_bytes     = 20'd0;
        mem_wr_data      = 64'd0;
        loader_start     = 1'b0;
        ld_data          = 64'b0;
        ld_valid         = 1'b0;
        enc_start        = 1'b0;
        in_we            = 1'b0;
        in_waddr         = 11'd0;
        in_wdata         = 64'd0;
        fc_start         = 1'b0;
        fc_sel           = 2'd0;
        fifo_we          = 1'b0;
        fifo_wdata       = 64'd0;

        // T-03 user-approved correction: a one-cycle Loader completion may
        // precede LD_WAIT. Capture its error on the SAME edge as its pulse.
        if (((state_reg == LD_RD1) || (state_reg == LD_RD2) ||
             (state_reg == LD_WAIT)) && loader_done) begin
            loader_done_seen_next = 1'b1;
            loader_error_seen_next = loader_err;
        end

        // FC completion is a pulse and may precede read completion.
        // Keep it until the read is idle; a new FC START clears it below.
        if (((state_reg == FC1) || (state_reg == FC2) ||
             (state_reg == FC3)) && fc_done)
            fc_done_seen_next = 1'b1;

        // D02 R3: CLEAR affects display only, never the pending execution result.
        if (reg_clear_status) begin
            done_next  = 1'b0;
            error_next = ERR_NONE;
        end

        case (state_reg)
            IDLE: begin
                if (reg_start) begin
                    // D03 R1: snapshot and busy update on the START sampling edge.
                    cmd_next         = reg_cmd;
                    input_addr_next  = reg_input_addr;
                    weight_addr_next = reg_weight_addr;
                    output_addr_next = reg_output_addr;
                    run_error_next   = ERR_NONE;
                    loader_done_seen_next = 1'b0;
                    loader_error_seen_next = 1'b0;
                    state_next       = DECODE;
                    // D02 R1: an accepted START clears the previous display.
                    done_next        = 1'b0;
                    error_next       = ERR_NONE;
                end
            end
            DECODE: begin
                // cmd_reg now contains THIS request's START snapshot; changes
                // to incoming reg_cmd cannot change the accepted command.
                // cfg_ok is observed in DECODE, not on the START sampling edge.
                // DECODE is one cycle; LOAD now launches the resident reads.
                if (cmd_reg == CMD_LOAD) begin
                    run_error_next = ERR_NONE;
                    loader_start = 1'b1;
                    mem_rd_start = 1'b1;
                    mem_rd_addr = weight_addr_reg;
                    mem_rd_bytes = 20'd5936;
                    // D06: remember the same snapshot used by this LOAD read.
                    load_base_next = weight_addr_reg;
                    // Both addresses belong to this NEW LOAD snapshot. Using
                    // the old load_base_reg here would lag one LOAD behind.
                    ld2_addr_next = weight_addr_reg + 32'd399152;
                    fc1_addr_next = load_base_next + 32'd5936;
                    state_next = LD_RD1;
                end else if ((cmd_reg == CMD_INFER) && cfg_ok) begin
                    run_error_next = ERR_NONE;
                    mem_rd_start = 1'b1;
                    mem_rd_addr = input_addr_reg;
                    mem_rd_bytes = 20'd11520;
                    beat_next = 11'd0;
                    state_next = IN_RD;
                end else if ((cmd_reg == CMD_INFER) && !cfg_ok) begin
                    run_error_next = ERR_NO_CFG;
                    state_next = FINISH;
                end else begin
                    run_error_next = ERR_BAD_CMD;
                    state_next = FINISH;
                end
            end
            LD_RD1: begin
                ld_valid = mem_rd_valid;
                ld_data = mem_rd_data;
                mem_rd_ready = ld_ready;
                // Error has priority over the falling busy edge (ASM-LOAD).
                if (mem_rd_err) begin
                    run_error_next = ERR_MEM_RD;
                    // D08: gate the consumer in THIS error-detection cycle,
                    // before entering the shared drain on the next edge.
                    ld_valid = 1'b0;
                    mem_rd_ready = 1'b1;
                    state_next = ERR_DRAIN;
                end else if (mem_rd_busy_prev_reg && !mem_rd_busy) begin
                    mem_rd_start = 1'b1;
                    mem_rd_addr = ld2_addr_reg;
                    mem_rd_bytes = 20'd23840;
                    state_next = LD_RD2;
                end
            end
            LD_RD2: begin
                ld_valid = mem_rd_valid;
                ld_data = mem_rd_data;
                mem_rd_ready = ld_ready;
                if (mem_rd_err) begin
                    run_error_next = ERR_MEM_RD;
                    ld_valid = 1'b0;
                    mem_rd_ready = 1'b1;
                    state_next = ERR_DRAIN;
                end else if (mem_rd_busy_prev_reg && !mem_rd_busy) begin
                    state_next = LD_WAIT;
                end
            end
            LD_WAIT: begin
                if (loader_done || loader_done_seen_reg) begin
                    if (loader_done ? loader_err : loader_error_seen_reg)
                        run_error_next = ERR_BLOB;
                    state_next = FINISH;
                end
            end
            IN_RD: begin
                mem_rd_ready = 1'b1;
                in_we = mem_rd_valid;
                in_waddr = beat_reg;
                in_wdata = mem_rd_data;
                // ASM-INFER priority: error, valid beat, then falling busy.
                if (mem_rd_err) begin
                    run_error_next = ERR_MEM_RD;
                    // D08: immediately stop the consumer, drain with READY=1.
                    // M00 registers an RRESP error after accepting that beat;
                    // this suppresses subsequent writes, not the accepted beat.
                    in_we = 1'b0;
                    state_next = ERR_DRAIN;
                end else if (mem_rd_valid) begin
                    beat_next = beat_reg + 11'd1;
                end else if (mem_rd_busy_prev_reg && !mem_rd_busy) begin
                    enc_start = 1'b1;
                    state_next = ENC;
                end
            end
            ENC: begin
                // A synchronous zero-delay done starts just after the edge
                // accepting enc_start; that edge also enters ENC, so it is seen.
                if (enc_done) begin
                    fc_start = 1'b1;
                    fc_sel = 2'd0;
                    fc_done_seen_next = 1'b0;
                    mem_rd_start = 1'b1;
                    // D06 confirmed: use the LOAD base, not this INFER snapshot.
                    mem_rd_addr = fc1_addr_reg;
                    mem_rd_bytes = 20'd393216;
                    state_next = FC1;
                end
            end
            FC1: begin
                fifo_we = mem_rd_valid && !fifo_full;
                mem_rd_ready = !fifo_full;
                fifo_wdata = mem_rd_data;
                // Error takes priority over both live and remembered completion.
                if (mem_rd_err) begin
                    run_error_next = ERR_MEM_RD;
                    fifo_we = 1'b0;
                    mem_rd_ready = 1'b1;
                    // Do not restart/abort active FC without a defined contract.
                    state_next = ERR_DRAIN;
                end else if ((fc_done || fc_done_seen_reg) && !mem_rd_busy) begin
                    fc_start = 1'b1;
                    fc_sel = 2'd1;
                    fc_done_seen_next = 1'b0;
                    state_next = FC2;
                end
            end
            FC2: begin
                if (fc_done || fc_done_seen_reg) begin
                    fc_start = 1'b1;
                    fc_sel = 2'd2;
                    fc_done_seen_next = 1'b0;
                    state_next = FC3;
                end
            end
            FC3: begin
                if (fc_done || fc_done_seen_reg) begin
                    mem_wr_start = 1'b1;
                    mem_wr_addr = output_addr_reg;
                    mem_wr_bytes = 20'd24;
                    beat_next = 11'd0;
                    state_next = WR;
                end
            end
            WR: begin
                // Explicit 64-bit slices avoid an out-of-range part select.
                // After the third transfer, keep the final word valid while
                // M00 waits for B. There is no fourth producer transfer.
                case (beat_reg)
                    11'd0: mem_wr_data = pose_data[63:0];
                    11'd1: mem_wr_data = pose_data[127:64];
                    default: mem_wr_data = pose_data[191:128];
                endcase
                if (mem_wr_ready) begin
                    // Consecutive HIGH cycles are distinct accepted beats.
                    if (beat_reg < 11'd3) beat_next = beat_reg + 11'd1;
                end else if (mem_wr_busy_prev_reg && !mem_wr_busy) begin
                    // Write errors are checked only after the final B response;
                    // M00 has already finished, so WR does not enter ERR_DRAIN.
                    if (mem_wr_err) run_error_next = ERR_MEM_WR;
                    state_next = FINISH;
                end
            end
            ERR_DRAIN: begin
                // Defaults suppress every consumer write/start and set data=0.
                // Keep accepting R beats, including while a write is outstanding.
                // Preserve run_error_reg; FINISH alone publishes STATUS.error.
                // RD_FAULT never clears busy: PS timeout/reset is the D08 policy.
                mem_rd_ready = 1'b1;
                if (!mem_rd_busy && !mem_wr_busy) state_next = FINISH;
            end
            FINISH: begin
                // D02 R2: publish only on the FINISH exit edge. R1's START
                // clear occurs on a different edge and cannot erase this result.
                // D02 R4: publish after CLEAR above, so the new result wins.
                // A START sampled here is ignored, including on this exit edge.
                state_next = IDLE;
                if (run_error_reg != ERR_NONE) begin
                    done_next  = 1'b0;
                    error_next = run_error_reg;
                end else begin
                    done_next  = 1'b1;
                    error_next = ERR_NONE;
                end
            end
            default: begin
                // Illegal state recovery preserves results; independent CLEAR
                // above still applies. No new success/error is manufactured.
                state_next = IDLE;
            end
        endcase
    end
endmodule
