`timescale 1ns/1ps
// Per-class score capture, highest-score selection and estimator-to-wire mapping.
module ridge_result #(parameter integer N_CLASSES=11)(
    input wire aclk, aresetn,
    input wire wr_ok, input wire [15:0] wr_addr, input wire [31:0] wr_data,
    input wire f_mac, last_feature, f_eval, last_class, input wire [3:0] class_idx,
    input wire signed [63:0] accumulator, sum_next,
    output reg [31:0] sptr, output wire [63:0] selected_score,
    output reg [3:0] result_estimator, result_wire,
    output reg signed [63:0] best_score
);
    localparam [15:0] REG_SPTR=16'h002c;
    reg signed [63:0] scores [0:N_CLASSES-1];
    reg [3:0] best_idx;
    assign selected_score = scores[sptr];
    always @(posedge aclk) begin
        if (!aresetn) begin
            sptr<=0; best_idx<=0; best_score<=0;
            result_estimator<=0; result_wire<=0;
        end else begin
            if (wr_ok && wr_addr==REG_SPTR) sptr<=wr_data;
            if (f_mac && last_feature) scores[class_idx]<=sum_next;
            if (f_eval) begin
                if (class_idx==0 || accumulator>best_score) begin
                    best_score<=accumulator; best_idx<=class_idx;
                end
                if (last_class) begin
                    if (class_idx==0 || accumulator>best_score) begin
                        result_estimator<=class_idx;
                        result_wire<=class_idx==0 ? 4'd10 : class_idx-1'b1;
                    end else begin
                        result_estimator<=best_idx;
                        result_wire<=best_idx==0 ? 4'd10 : best_idx-1'b1;
                    end
                end
            end
        end
    end
endmodule
