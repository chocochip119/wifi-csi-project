`timescale 1 ns / 1 ps

// L-03: resident LOAD framing, Conv/Param/FCW/LUT writes and header/shift checks.
// 05_Loader r36-r61 / 09_Loader_주소맵 r7-r40; synchronous active-low reset.
// Conv scatter uses byte-advanced tap/output-channel counters; no division/modulo.
module blob_decoder #(
    parameter [31:0] EXPECTED_MAGIC = 32'h36574c50,
    parameter [31:0] EXPECTED_VERSION = 32'd2,
    parameter [31:0] EXPECTED_TOTAL_WORDS = 32'd105748,
    // Version 2 confirmed against full_pose.h and the reference blob (L-02).
    parameter CHECK_VERSION = 1'b1
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         loader_start,
    output wire         loader_done,
    output wire         loader_err,
    input  wire [63:0]  ld_data,
    input  wire         ld_valid,
    output reg          ld_ready,
    output wire         cfg_ok,
    output wire [31:0]  output_scale_bits,
    output wire [31:0]  pool_mult,
    output wire [31:0]  pool_shift,
    output reg          conv_we,
    output reg  [8:0]   conv_waddr,
    output reg  [127:0] conv_wdata,
    output reg  [15:0]  conv_wstrb,
    output reg          param_we,
    output reg  [8:0]   param_waddr,
    output reg  [95:0]  param_wdata,
    output reg  [2:0]   param_wstrb,
    output reg          lut_we,
    output reg  [9:0]   lut_waddr,
    output reg  [7:0]   lut_wdata,
    output reg          fcw_we,
    output reg  [11:0]  fcw_waddr,
    output reg  [63:0]  fcw_wdata
);
    localparam [1:0] IDLE = 2'd0, RECEIVE = 2'd1, WORK = 2'd2, DRAIN = 2'd3;
    localparam [3:0] HEADER = 4'd0, CONV1_W = 4'd1, CONV1_P = 4'd2;
    localparam [3:0] CONV2_W = 4'd3, CONV2_P = 4'd4, FC1_P = 4'd5;
    localparam [3:0] FC2_W = 4'd6, FC2_P = 4'd7, FC3_W = 4'd8;
    localparam [3:0] FC3_P = 4'd9, GELU = 4'd10, NO_REGION = 4'd15;
    localparam [11:0] STREAM_BEATS = 12'd3722;

    reg [1:0] state_reg, state_next;
    // Number already accepted; before a handshake it is that beat's index.
    // 3722 is the terminal count, never an accepted beat index or a RAM address.
    reg [11:0] beat_count_reg, beat_count_next;
    reg [2:0] work_left_reg, work_left_next;
    reg [63:0] beat_data_reg, beat_data_next;
    reg [3:0] processing_region_reg, processing_region_next;
    reg error_reg, error_next;
    reg done_reg, done_next, done_error_reg, done_error_next;
    reg cfg_reg, cfg_next;
    reg [31:0] output_scale_reg, output_scale_next;
    reg [31:0] pool_mult_reg, pool_mult_next, pool_shift_reg, pool_shift_next;


    // Advance only when a Conv byte is written. Each Conv region starts at 0/0.
    reg [7:0] conv_tap_reg, conv_tap_next;
    reg [4:0] conv_oc_reg, conv_oc_next;
    reg [7:0] conv_tap_value, conv_byte;
    reg [4:0] conv_oc_value;
    reg conv_pending, conv_second;
    reg [8:0] param_addr_dec;
    reg [2:0] param_strobe_dec;
    reg [8:0] param_addr_reg, param_addr_next;
    reg [2:0] param_strobe_reg, param_strobe_next;
    reg [9:0] lut_addr_reg, lut_addr_next;
    wire param_shift_bad = (param_strobe_dec == 3'b100) &&
        (($signed(ld_data[31:0]) < -32'sd31) || ($signed(ld_data[31:0]) > 32'sd63) ||
         ($signed(ld_data[63:32]) < -32'sd31) || ($signed(ld_data[63:32]) > 32'sd63));

    // 09_Loader rows 26-35. Each field array starts again at its layer base.
    // Explicit ranges avoid division/modulo and keep signed data out of addresses.
    always @(*) begin
        param_addr_dec = 9'd0;
        param_strobe_dec = 3'b000;
        if ((beat_count_reg >= 12'd94) && (beat_count_reg < 12'd102)) begin
            param_addr_dec = 9'd0 + ((beat_count_reg - 12'd94) << 1);
            param_strobe_dec = 3'd1;
        end else if ((beat_count_reg >= 12'd102) && (beat_count_reg < 12'd110)) begin
            param_addr_dec = 9'd0 + ((beat_count_reg - 12'd102) << 1);
            param_strobe_dec = 3'd2;
        end else if ((beat_count_reg >= 12'd110) && (beat_count_reg < 12'd118)) begin
            param_addr_dec = 9'd0 + ((beat_count_reg - 12'd110) << 1);
            param_strobe_dec = 3'd4;
        end else if ((beat_count_reg >= 12'd694) && (beat_count_reg < 12'd710)) begin
            param_addr_dec = 9'd16 + ((beat_count_reg - 12'd694) << 1);
            param_strobe_dec = 3'd1;
        end else if ((beat_count_reg >= 12'd710) && (beat_count_reg < 12'd726)) begin
            param_addr_dec = 9'd16 + ((beat_count_reg - 12'd710) << 1);
            param_strobe_dec = 3'd2;
        end else if ((beat_count_reg >= 12'd726) && (beat_count_reg < 12'd742)) begin
            param_addr_dec = 9'd16 + ((beat_count_reg - 12'd726) << 1);
            param_strobe_dec = 3'd4;
        end else if ((beat_count_reg >= 12'd742) && (beat_count_reg < 12'd806)) begin
            param_addr_dec = 9'd48 + ((beat_count_reg - 12'd742) << 1);
            param_strobe_dec = 3'd1;
        end else if ((beat_count_reg >= 12'd806) && (beat_count_reg < 12'd870)) begin
            param_addr_dec = 9'd48 + ((beat_count_reg - 12'd806) << 1);
            param_strobe_dec = 3'd2;
        end else if ((beat_count_reg >= 12'd870) && (beat_count_reg < 12'd934)) begin
            param_addr_dec = 9'd48 + ((beat_count_reg - 12'd870) << 1);
            param_strobe_dec = 3'd4;
        end else if ((beat_count_reg >= 12'd2982) && (beat_count_reg < 12'd3046)) begin
            param_addr_dec = 9'd176 + ((beat_count_reg - 12'd2982) << 1);
            param_strobe_dec = 3'd1;
        end else if ((beat_count_reg >= 12'd3046) && (beat_count_reg < 12'd3110)) begin
            param_addr_dec = 9'd176 + ((beat_count_reg - 12'd3046) << 1);
            param_strobe_dec = 3'd2;
        end else if ((beat_count_reg >= 12'd3110) && (beat_count_reg < 12'd3174)) begin
            param_addr_dec = 9'd176 + ((beat_count_reg - 12'd3110) << 1);
            param_strobe_dec = 3'd4;
        end else if ((beat_count_reg >= 12'd3558) && (beat_count_reg < 12'd3570)) begin
            param_addr_dec = 9'd304 + ((beat_count_reg - 12'd3558) << 1);
            param_strobe_dec = 3'd1;
        end else if ((beat_count_reg >= 12'd3570) && (beat_count_reg < 12'd3582)) begin
            param_addr_dec = 9'd304 + ((beat_count_reg - 12'd3570) << 1);
            param_strobe_dec = 3'd2;
        end else if ((beat_count_reg >= 12'd3582) && (beat_count_reg < 12'd3594)) begin
            param_addr_dec = 9'd304 + ((beat_count_reg - 12'd3582) << 1);
            param_strobe_dec = 3'd4;
        end
    end

    // Internal observation signals: no extra shared interface ports are added.
    reg [3:0] region_code, region_writes;
    always @(*) begin
        region_code = NO_REGION;
        region_writes = 4'd1;
        if (beat_count_reg < 12'd4) begin
            region_code = HEADER;
        end else if (beat_count_reg < 12'd94) begin
            region_code = CONV1_W; region_writes = 4'd8;
        end else if (beat_count_reg < 12'd118) begin
            region_code = CONV1_P; region_writes = 4'd2;
        end else if (beat_count_reg < 12'd694) begin
            region_code = CONV2_W; region_writes = 4'd8;
        end else if (beat_count_reg < 12'd742) begin
            region_code = CONV2_P; region_writes = 4'd2;
        end else if (beat_count_reg < 12'd934) begin
            region_code = FC1_P; region_writes = 4'd2;
        end else if (beat_count_reg < 12'd2982) begin
            region_code = FC2_W;
        end else if (beat_count_reg < 12'd3174) begin
            region_code = FC2_P; region_writes = 4'd2;
        end else if (beat_count_reg < 12'd3558) begin
            region_code = FC3_W;
        end else if (beat_count_reg < 12'd3594) begin
            region_code = FC3_P; region_writes = 4'd2;
        end else if (beat_count_reg < STREAM_BEATS) begin
            region_code = GELU; region_writes = 4'd8;
        end
    end

    assign loader_done = done_reg;
    assign loader_err = done_error_reg;
    assign cfg_ok = cfg_reg;
    assign output_scale_bits = output_scale_reg;
    assign pool_mult = pool_mult_reg;
    assign pool_shift = pool_shift_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            state_reg <= IDLE;
            beat_count_reg <= 12'd0;
            work_left_reg <= 3'd0;
            conv_tap_reg <= 8'd0;
            conv_oc_reg <= 5'd0;
            param_addr_reg <= 9'd0;
            param_strobe_reg <= 3'd0;
            lut_addr_reg <= 10'd0;
            beat_data_reg <= 64'd0;
            processing_region_reg <= NO_REGION;
            error_reg <= 1'b0;
            done_reg <= 1'b0;
            done_error_reg <= 1'b0;
            cfg_reg <= 1'b0;
            output_scale_reg <= 32'd0;
            pool_mult_reg <= 32'd0;
            pool_shift_reg <= 32'd0;
        end else begin
            state_reg <= state_next;
            beat_count_reg <= beat_count_next;
            work_left_reg <= work_left_next;
            conv_tap_reg <= conv_tap_next;
            conv_oc_reg <= conv_oc_next;
            param_addr_reg <= param_addr_next;
            param_strobe_reg <= param_strobe_next;
            lut_addr_reg <= lut_addr_next;
            beat_data_reg <= beat_data_next;
            processing_region_reg <= processing_region_next;
            error_reg <= error_next;
            done_reg <= done_next;
            done_error_reg <= done_error_next;
            cfg_reg <= cfg_next;
            output_scale_reg <= output_scale_next;
            pool_mult_reg <= pool_mult_next;
            pool_shift_reg <= pool_shift_next;
        end
    end

    always @(*) begin
        state_next = state_reg;
        beat_count_next = beat_count_reg;
        work_left_next = work_left_reg;
        conv_tap_next = conv_tap_reg;
        conv_oc_next = conv_oc_reg;
        conv_tap_value = conv_tap_reg;
        conv_oc_value = conv_oc_reg;
        conv_pending = 1'b0;
        conv_second = 1'b0;
        conv_byte = 8'd0;
        conv_we = 1'b0; conv_waddr = 9'd0; conv_wdata = 128'd0; conv_wstrb = 16'd0;
        param_addr_next = param_addr_reg;
        param_strobe_next = param_strobe_reg;
        lut_addr_next = lut_addr_reg;
        beat_data_next = beat_data_reg;
        processing_region_next = processing_region_reg;
        error_next = error_reg;
        done_next = 1'b0;
        done_error_next = 1'b0;
        cfg_next = cfg_reg;
        output_scale_next = output_scale_reg;
        pool_mult_next = pool_mult_reg;
        pool_shift_next = pool_shift_reg;
        ld_ready = 1'b0;
        param_we = 1'b0; param_waddr = 9'd0; param_wdata = 96'd0; param_wstrb = 3'd0;
        fcw_we = 1'b0; fcw_waddr = 12'd0; fcw_wdata = 64'd0;
        lut_we = 1'b0; lut_waddr = 10'd0; lut_wdata = 8'd0;

        case (state_reg)
            IDLE: begin
                if (loader_start) begin
                    state_next = RECEIVE;
                    beat_count_next = 12'd0;
                    work_left_next = 3'd0;
                    conv_tap_next = 8'd0;
                    conv_oc_next = 5'd0;
                    param_addr_next = 9'd0;
                    param_strobe_next = 3'd0;
                    lut_addr_next = 10'd0;
                    beat_data_next = 64'd0;
                    processing_region_next = NO_REGION;
                    error_next = 1'b0;
                    cfg_next = 1'b0;
                    output_scale_next = 32'd0;
                    pool_mult_next = 32'd0;
                    pool_shift_next = 32'd0;
                end
            end
            RECEIVE: begin
                ld_ready = 1'b1;
                if (ld_valid) begin
                    beat_count_next = beat_count_reg + 12'd1;
                    beat_data_next = ld_data;
                    processing_region_next = region_code;
                    // Low word is even, high word odd. Header work costs 1 cycle.
                    if (beat_count_reg == 12'd0) begin
                        if ((ld_data[31:0] != EXPECTED_MAGIC) ||
                            (CHECK_VERSION && (ld_data[63:32] != EXPECTED_VERSION)))
                            error_next = 1'b1;
                    end else if (beat_count_reg == 12'd1) begin
                        if (ld_data[31:0] != EXPECTED_TOTAL_WORDS) error_next = 1'b1;
                    end else if (beat_count_reg == 12'd2) begin
                        output_scale_next = ld_data[31:0];
                        pool_mult_next = ld_data[63:32];
                    end else if (beat_count_reg == 12'd3) begin
                        pool_shift_next = ld_data[31:0];
                        if (($signed(ld_data[31:0]) < -32'sd31) ||
                            ($signed(ld_data[31:0]) > 32'sd63)) error_next = 1'b1;
                    end
                    // Validate BOTH words before the first field write. A malformed
                    // shift beat performs no writes; all subsequent beats are drained.
                    if (param_shift_bad) error_next = 1'b1;
                    // Conv regions cannot detect a new header/shift error. Keep
                    // live header data out of their address path; error_reg still
                    // blocks all Conv writes in the common write block below.
                    if ((region_code == CONV1_W) || (region_code == CONV2_W)) begin
                        conv_pending = 1'b1;
                        conv_second = (region_code == CONV2_W);
                        conv_byte = ld_data[7:0];
                        if ((beat_count_reg == 12'd4) || (beat_count_reg == 12'd118)) begin
                            conv_tap_value = 8'd0;
                            conv_oc_value = 5'd0;
                        end
                    end
                    if (!error_next) begin
                        if (param_strobe_dec != 3'd0) begin
                            param_we = 1'b1;
                            param_waddr = param_addr_dec;
                            param_wdata = {3{ld_data[31:0]}};
                            param_wstrb = param_strobe_dec;
                            param_addr_next = param_addr_dec + 9'd1;
                            param_strobe_next = param_strobe_dec;
                        end else if ((region_code == FC2_W) || (region_code == FC3_W)) begin
                            fcw_we = 1'b1;
                            fcw_waddr = (region_code == FC2_W) ?
                                (beat_count_reg - 12'd934) : (12'd2048 + beat_count_reg - 12'd3174);
                            fcw_wdata = ld_data;
                        end else if (region_code == GELU) begin
                            lut_we = 1'b1;
                            lut_waddr = (beat_count_reg - 12'd3594) << 3;
                            lut_wdata = ld_data[7:0];
                            lut_addr_next = lut_waddr + 10'd1;
                        end
                    end
                    // Header/shift failure records an error immediately, but NEVER
                    // stops the stream. Top still has both resident reads to do.
                    if (error_next) state_next = DRAIN;
                    else if (region_writes == 4'd8) begin
                        work_left_next = 3'd7; state_next = WORK;
                    end else if (region_writes == 4'd2) begin
                        work_left_next = 3'd1; state_next = WORK;
                    end
                    // One operation is on the acceptance edge; the remaining
                    // 7/1 operations occupy WORK. FCW/header need no extra edge.
                end
            end
            WORK: begin
                // User-confirmed D6 scope: only BEFORE completion, while the
                // final beat is processing, an additional offered VALID is an
                // overlength error. It is not accepted and cannot wrap the count.
                // No EOF port exists to attribute late idle traffic to this LOAD.
                if ((beat_count_reg == STREAM_BEATS) && ld_valid) error_next = 1'b1;
                // The terminal extra-VALID check belongs to the LUT region,
                // never to Conv work. No new error is detected in a Conv cycle.
                if ((processing_region_reg == CONV1_W) || (processing_region_reg == CONV2_W)) begin
                    conv_pending = 1'b1;
                    conv_second = (processing_region_reg == CONV2_W);
                    case (work_left_reg)
                        3'd7: conv_byte = beat_data_reg[15:8];
                        3'd6: conv_byte = beat_data_reg[23:16];
                        3'd5: conv_byte = beat_data_reg[31:24];
                        3'd4: conv_byte = beat_data_reg[39:32];
                        3'd3: conv_byte = beat_data_reg[47:40];
                        3'd2: conv_byte = beat_data_reg[55:48];
                        3'd1: conv_byte = beat_data_reg[63:56];
                        default: conv_byte = 8'd0;
                    endcase
                end
                if (!error_next) begin
                    if ((processing_region_reg == CONV1_P) || (processing_region_reg == CONV2_P) ||
                        (processing_region_reg == FC1_P) || (processing_region_reg == FC2_P) ||
                        (processing_region_reg == FC3_P)) begin
                        param_we = 1'b1;
                        param_waddr = param_addr_reg;
                        param_wdata = {3{beat_data_reg[63:32]}};
                        param_wstrb = param_strobe_reg;
                    end else if (processing_region_reg == GELU) begin
                        lut_we = 1'b1;
                        lut_waddr = lut_addr_reg;
                        lut_addr_next = lut_addr_reg + 10'd1;
                        case (work_left_reg)
                            3'd7: lut_wdata = beat_data_reg[15:8];
                            3'd6: lut_wdata = beat_data_reg[23:16];
                            3'd5: lut_wdata = beat_data_reg[31:24];
                            3'd4: lut_wdata = beat_data_reg[39:32];
                            3'd3: lut_wdata = beat_data_reg[47:40];
                            3'd2: lut_wdata = beat_data_reg[55:48];
                            3'd1: lut_wdata = beat_data_reg[63:56];
                            default: lut_wdata = 8'd0;
                        endcase
                    end
                end
                work_left_next = work_left_reg - 3'd1;
                if (work_left_reg == 3'd1) begin
                    if (beat_count_reg == STREAM_BEATS) begin
                        state_next = IDLE;
                        done_next = 1'b1;
                        done_error_next = error_next;
                        cfg_next = !error_next;
                    end else state_next = RECEIVE;
                end
            end
            DRAIN: begin
                ld_ready = 1'b1;
                if (ld_valid) begin
                    beat_count_next = beat_count_reg + 12'd1;
                    if (beat_count_reg == STREAM_BEATS - 12'd1) begin
                        state_next = IDLE;
                        done_next = 1'b1;
                        done_error_next = 1'b1;
                        cfg_next = 1'b0;
                    end
                end
            end
            default: begin
                state_next = IDLE;
                cfg_next = 1'b0;
            end
        endcase
        // 09_Loader r25/r29: compute one (word,lane) pair for EACH byte.
        // Conv1 wraps at tap 44 even in the middle of a beat; Conv2 at tap 143.
        if (conv_pending && !error_reg && rst_n) begin
            conv_we = 1'b1;
            conv_waddr = {1'b0, conv_tap_value};
            if (conv_second)
                conv_waddr = (conv_oc_value[4] ? 9'd189 : 9'd45) + {1'b0, conv_tap_value};
            conv_wstrb = 16'b1 << conv_oc_value[3:0];
            conv_wdata[{conv_oc_value[3:0],3'b000} +: 8] = conv_byte;
            if ((!conv_second && (conv_tap_value == 8'd44)) ||
                (conv_second && (conv_tap_value == 8'd143))) begin
                conv_tap_next = 8'd0;
                conv_oc_next = conv_oc_value + 5'd1;
            end else begin
                conv_tap_next = conv_tap_value + 8'd1;
                conv_oc_next = conv_oc_value;
            end
        end
        // RAMs intentionally have no reset. Do not write during a control reset edge.
        if (!rst_n) begin
            param_we = 1'b0;
            fcw_we = 1'b0;
            lut_we = 1'b0;
        end
    end
endmodule
