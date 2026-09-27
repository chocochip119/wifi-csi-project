`timescale 1ns / 1ps

// F-02 / 08_FC r46-r57. Eight signed INT8 products per accepted input word.
// acc is the pure dot product; bias belongs to the later requant stage.
// hidden_raddr = {bank, word[3:0]}; split these fields at hidden_buffer.
module fc_mac (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               mac_start,
    input  wire [1:0]         mac_sel,
    output wire               mac_done,
    output wire [8:0]         flat_raddr,
    input  wire [63:0]        flat_rdata,
    output wire               fifo_re,
    input  wire [63:0]        fifo_rdata,
    input  wire               fifo_empty,
    output wire [4:0]         hidden_raddr,
    input  wire [63:0]        hidden_rdata,
    output wire [11:0]        fcw_raddr,
    input  wire [63:0]        fcw_rdata,
    output wire signed [31:0] acc,
    output wire               acc_valid,
    output wire [8:0]         acc_tag
);
    localparam [1:0] IDLE = 2'd0, ISSUE = 2'd1, DRAIN = 2'd2, DONE = 2'd3;
    reg [1:0] state_reg, state_next, sel_reg, sel_next;
    reg [8:0] word_reg, word_next;
    reg [6:0] out_reg, out_next;
    reg [5:0] valid_reg, valid_next;
    // Metadata: {first_word, last_word, last_layer_word, tag[8:0]}.
    reg [11:0] read_meta_reg, read_meta_next, operand_meta_reg, operand_meta_next;
    reg [11:0] product_meta_reg, product_meta_next, pair_meta_reg, pair_meta_next;
    reg [11:0] quad_meta_reg, quad_meta_next, sum_meta_reg, sum_meta_next;
    reg [63:0] fifo_word_reg, fifo_word_next;
    reg [63:0] act_reg, act_next, weight_reg, weight_next;
    reg signed [15:0] p0_reg, p0_next, p1_reg, p1_next, p2_reg, p2_next, p3_reg, p3_next;
    reg signed [15:0] p4_reg, p4_next, p5_reg, p5_next, p6_reg, p6_next, p7_reg, p7_next;
    reg signed [16:0] pair0_reg, pair0_next, pair1_reg, pair1_next;
    reg signed [16:0] pair2_reg, pair2_next, pair3_reg, pair3_next;
    reg signed [17:0] quad0_reg, quad0_next, quad1_reg, quad1_next;
    reg signed [18:0] sum_reg, sum_next;
    reg signed [31:0] running_reg, running_next, acc_reg, acc_next;
    reg valid_out_reg, valid_out_next, done_reg, done_next;
    reg [8:0] tag_reg, tag_next;

    wire issue = (state_reg == ISSUE) && ((sel_reg != 2'd0) || !fifo_empty);
    wire last_word = (sel_reg == 2'd0) ? (word_reg == 9'd383) : (word_reg == 9'd15);
    wire last_output = (sel_reg == 2'd2) ? (out_reg == 7'd23) : (out_reg == 7'd127);
    wire signed [31:0] extended_sum = {{13{sum_reg[18]}}, sum_reg};

    assign flat_raddr = (state_reg == ISSUE && sel_reg == 2'd0) ? word_reg : 9'd0;
    assign hidden_raddr = (state_reg == ISSUE && sel_reg != 2'd0) ?
                          {sel_reg == 2'd2, word_reg[3:0]} : 5'd0;
    assign fcw_raddr = (state_reg == ISSUE && sel_reg != 2'd0) ?
                       {sel_reg == 2'd2, out_reg, word_reg[3:0]} : 12'd0;
    assign fifo_re = issue && (sel_reg == 2'd0);
    assign acc = acc_reg;
    assign acc_valid = valid_out_reg;
    assign acc_tag = tag_reg;
    assign mac_done = done_reg;

    // At issue edge E the RAM samples raddr and the FWFT FIFO is popped.
    // fifo_word_reg captures the old FIFO head at E. At E+1 both that saved
    // weight and synchronous RAM activation are captured as operands.
    // FC2/3 RAM activation and weight are likewise paired at E+1.
    // E+2 products, E+3 pairs, E+4 quads, E+5 group sum, E+6 accumulation.
    // Issue gaps insert valid bubbles; address/index advances only on issue.
    // The arithmetic pipeline drains normally during a FIFO-empty pause.
    always @(*) begin
        state_next = state_reg;
        sel_next = sel_reg;
        word_next = word_reg;
        out_next = out_reg;
        valid_next = {valid_reg[4:0], issue};
        read_meta_next = read_meta_reg;
        operand_meta_next = operand_meta_reg;
        product_meta_next = product_meta_reg;
        pair_meta_next = pair_meta_reg;
        quad_meta_next = quad_meta_reg;
        sum_meta_next = sum_meta_reg;
        fifo_word_next = fifo_word_reg;
        act_next = act_reg;
        weight_next = weight_reg;
        p0_next = p0_reg; p1_next = p1_reg; p2_next = p2_reg; p3_next = p3_reg;
        p4_next = p4_reg; p5_next = p5_reg; p6_next = p6_reg; p7_next = p7_reg;
        pair0_next = pair0_reg; pair1_next = pair1_reg;
        pair2_next = pair2_reg; pair3_next = pair3_reg;
        quad0_next = quad0_reg; quad1_next = quad1_reg;
        sum_next = sum_reg;
        running_next = running_reg;
        acc_next = acc_reg;
        tag_next = tag_reg;
        valid_out_next = 1'b0;
        done_next = 1'b0;

        if (issue) begin
            read_meta_next = {word_reg == 9'd0, last_word, last_word && last_output, sel_reg, out_reg};
            if (sel_reg == 2'd0)
                fifo_word_next = fifo_rdata;
            if (last_word) begin
                word_next = 9'd0;
                if (last_output)
                    state_next = DRAIN;
                else
                    out_next = out_reg + 7'd1;
            end else
                word_next = word_reg + 9'd1;
        end

        if (valid_reg[0]) begin
            act_next = (sel_reg == 2'd0) ? flat_rdata : hidden_rdata;
            weight_next = (sel_reg == 2'd0) ? fifo_word_reg : fcw_rdata;
            operand_meta_next = read_meta_reg;
        end
        if (valid_reg[1]) begin
            p0_next = $signed(act_reg[7:0])   * $signed(weight_reg[7:0]);
            p1_next = $signed(act_reg[15:8])  * $signed(weight_reg[15:8]);
            p2_next = $signed(act_reg[23:16]) * $signed(weight_reg[23:16]);
            p3_next = $signed(act_reg[31:24]) * $signed(weight_reg[31:24]);
            p4_next = $signed(act_reg[39:32]) * $signed(weight_reg[39:32]);
            p5_next = $signed(act_reg[47:40]) * $signed(weight_reg[47:40]);
            p6_next = $signed(act_reg[55:48]) * $signed(weight_reg[55:48]);
            p7_next = $signed(act_reg[63:56]) * $signed(weight_reg[63:56]);
            product_meta_next = operand_meta_reg;
        end
        if (valid_reg[2]) begin
            pair0_next = $signed({p0_reg[15], p0_reg}) + $signed({p1_reg[15], p1_reg});
            pair1_next = $signed({p2_reg[15], p2_reg}) + $signed({p3_reg[15], p3_reg});
            pair2_next = $signed({p4_reg[15], p4_reg}) + $signed({p5_reg[15], p5_reg});
            pair3_next = $signed({p6_reg[15], p6_reg}) + $signed({p7_reg[15], p7_reg});
            pair_meta_next = product_meta_reg;
        end
        if (valid_reg[3]) begin
            quad0_next = $signed({pair0_reg[16], pair0_reg}) + $signed({pair1_reg[16], pair1_reg});
            quad1_next = $signed({pair2_reg[16], pair2_reg}) + $signed({pair3_reg[16], pair3_reg});
            quad_meta_next = pair_meta_reg;
        end
        if (valid_reg[4]) begin
            sum_next = $signed({quad0_reg[17], quad0_reg}) + $signed({quad1_reg[17], quad1_reg});
            sum_meta_next = quad_meta_reg;
        end
        if (valid_reg[5]) begin
            running_next = sum_meta_reg[11] ? extended_sum : (running_reg + extended_sum);
            if (sum_meta_reg[10]) begin
                acc_next = running_next;
                tag_next = sum_meta_reg[8:0];
                valid_out_next = 1'b1;
            end
        end

        case (state_reg)
            IDLE: begin
                // Reserved mac_sel=3 is ignored. Starts in other states are ignored.
                if (mac_start && mac_sel != 2'd3) begin
                    sel_next = mac_sel;
                    word_next = 9'd0;
                    out_next = 7'd0;
                    state_next = ISSUE;
                end
            end
            ISSUE: begin end
            DRAIN: begin
                if (valid_reg[5] && sum_meta_reg[9])
                    state_next = DONE;
            end
            DONE: begin
                // Last acc_valid was asserted one edge earlier.
                done_next = 1'b1;
                state_next = IDLE;
            end
            default: state_next = IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state_reg <= IDLE; sel_reg <= 2'd0; word_reg <= 9'd0; out_reg <= 7'd0;
            valid_reg <= 6'd0;
            read_meta_reg <= 12'd0; operand_meta_reg <= 12'd0; product_meta_reg <= 12'd0;
            pair_meta_reg <= 12'd0; quad_meta_reg <= 12'd0; sum_meta_reg <= 12'd0;
            fifo_word_reg <= 64'd0; act_reg <= 64'd0; weight_reg <= 64'd0;
            p0_reg <= 16'sd0; p1_reg <= 16'sd0; p2_reg <= 16'sd0; p3_reg <= 16'sd0;
            p4_reg <= 16'sd0; p5_reg <= 16'sd0; p6_reg <= 16'sd0; p7_reg <= 16'sd0;
            pair0_reg <= 17'sd0; pair1_reg <= 17'sd0; pair2_reg <= 17'sd0; pair3_reg <= 17'sd0;
            quad0_reg <= 18'sd0; quad1_reg <= 18'sd0; sum_reg <= 19'sd0;
            running_reg <= 32'sd0; acc_reg <= 32'sd0; tag_reg <= 9'd0;
            valid_out_reg <= 1'b0; done_reg <= 1'b0;
        end else begin
            state_reg <= state_next; sel_reg <= sel_next; word_reg <= word_next; out_reg <= out_next;
            valid_reg <= valid_next;
            read_meta_reg <= read_meta_next; operand_meta_reg <= operand_meta_next;
            product_meta_reg <= product_meta_next; pair_meta_reg <= pair_meta_next;
            quad_meta_reg <= quad_meta_next; sum_meta_reg <= sum_meta_next;
            fifo_word_reg <= fifo_word_next; act_reg <= act_next; weight_reg <= weight_next;
            p0_reg <= p0_next; p1_reg <= p1_next; p2_reg <= p2_next; p3_reg <= p3_next;
            p4_reg <= p4_next; p5_reg <= p5_next; p6_reg <= p6_next; p7_reg <= p7_next;
            pair0_reg <= pair0_next; pair1_reg <= pair1_next; pair2_reg <= pair2_next; pair3_reg <= pair3_next;
            quad0_reg <= quad0_next; quad1_reg <= quad1_next; sum_reg <= sum_next;
            running_reg <= running_next; acc_reg <= acc_next; tag_reg <= tag_next;
            valid_out_reg <= valid_out_next; done_reg <= done_next;
        end
    end
endmodule
