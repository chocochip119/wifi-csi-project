`timescale 1ns/1ps
// Sequencing/status: one MAC shared by all 11 classes, 3 cycles per feature + EVAL.
module ridge_ctrl #(
    parameter integer N_FEATURES=955, N_CLASSES=11
)(
    input wire aclk, aresetn,
    input wire wr_ok, input wire [15:0] wr_addr,
    input wire wr_error, input wire [31:0] wr_error_code,
    input wire start_ok, commit_ok, commit_incomplete, clear_ok,
    output reg model_valid, busy, done, error_flag,
    output reg [31:0] error_code, cycles,
    output reg [3:0] class_idx, output reg [9:0] feature_idx,
    output reg [13:0] weight_idx,
    output wire f_fetch, f_mul, f_mac, f_eval,
    output wire last_feature, last_class, class_next
);
    localparam [15:0] REG_WPTR=16'h000c, REG_WDATA=16'h0010,
        REG_BPTR=16'h0014, REG_BLO=16'h0018, REG_BHI=16'h001c,
        REG_XPTR=16'h0020;
    localparam [2:0] S_IDLE=0, S_FETCH=1, S_MUL=2, S_MAC=3, S_EVAL=4;
    reg [2:0] state;
    assign f_fetch = (state==S_FETCH);
    assign f_mul   = (state==S_MUL);
    assign f_mac   = (state==S_MAC);
    assign f_eval  = (state==S_EVAL);
    assign last_feature = (feature_idx==N_FEATURES-1);
    assign last_class   = (class_idx==N_CLASSES-1);
    assign class_next = f_eval && !last_class;
    always @(posedge aclk) begin
        if (!aresetn) begin
            model_valid<=0; busy<=0; done<=0; error_flag<=0; error_code<=0;
            cycles<=0; class_idx<=0; feature_idx<=0; weight_idx<=0; state<=S_IDLE;
        end else begin
            // AXI writes are handled before FSM in the original always block;
            // FSM completion on the same edge therefore has the same precedence.
            if (wr_error) begin
                error_flag<=1; error_code<=wr_error_code;
            end
            if (clear_ok) begin
                done<=0; error_flag<=0; error_code<=0;
            end
            if (commit_incomplete) begin
                model_valid<=0; done<=0;
            end
            if (commit_ok) begin
                model_valid<=1; done<=0;
            end
            if (wr_ok) begin
                case (wr_addr)
                    REG_WPTR, REG_WDATA, REG_BPTR, REG_BLO, REG_BHI: begin
                        model_valid<=0; done<=0;
                    end
                    REG_XPTR: done<=0;
                endcase
            end
            if (start_ok) begin
                done<=0; error_flag<=0; error_code<=0;
                busy<=1; state<=S_FETCH;
                class_idx<=0; feature_idx<=0; weight_idx<=0; cycles<=0;
            end
            case (state)
                S_IDLE: ;
                S_FETCH: begin cycles<=cycles+1; state<=S_MUL; end
                S_MUL:   begin cycles<=cycles+1; state<=S_MAC; end
                S_MAC: begin
                    cycles<=cycles+1; weight_idx<=weight_idx+1;
                    if (last_feature) state<=S_EVAL;
                    else begin feature_idx<=feature_idx+1; state<=S_FETCH; end
                end
                S_EVAL: begin
                    cycles<=cycles+1;
                    if (last_class) begin busy<=0; done<=1; state<=S_IDLE; end
                    else begin class_idx<=class_idx+1; feature_idx<=0; state<=S_FETCH; end
                end
                default: state<=S_IDLE;
            endcase
        end
    end
endmodule
