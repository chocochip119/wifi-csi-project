`timescale 1ns/1ps
// Packed INT16 weights (32-bit BRAM words), per-class INT64 biases, load counters.
// BRAM contents and biases intentionally NOT reset (same as original RTL).
module ridge_model_mem #(
    parameter integer N_WWORDS=5253, N_CLASSES=11
)(
    input wire aclk, aresetn,
    input wire wr_ok, input wire [15:0] wr_addr, input wire [31:0] wr_data,
    input wire fetch, input wire [13:0] weight_idx, input wire [3:0] class_idx,
    output reg [31:0] wptr, wcount, bptr, bcount,
    output reg bias_low_valid,
    output reg [31:0] w_read_q,
    output wire signed [63:0] bias0, bias_next
);
    localparam [15:0] REG_WPTR=16'h000c, REG_WDATA=16'h0010,
        REG_BPTR=16'h0014, REG_BLO=16'h0018, REG_BHI=16'h001c;
    (* ram_style = "block" *) reg [31:0] weight_ram [0:N_WWORDS-1];
    reg signed [63:0] biases [0:N_CLASSES-1];
    reg [31:0] bias_low_latch;
    assign bias0 = biases[0];
    // class_idx+1 is used only when class_idx is not the last class.
    assign bias_next = biases[class_idx+1'b1];
    always @(posedge aclk) begin
        if (!aresetn) begin
            wptr<=0; wcount<=0; bptr<=0; bcount<=0;
            bias_low_latch<=0; bias_low_valid<=0;
            w_read_q<=0;
        end else begin
            // A synchronous BRAM read, using the same FETCH cycle as monolithic RTL.
            if (fetch) w_read_q<=weight_ram[weight_idx[13:1]];
            if (wr_ok) begin
                case (wr_addr)
                    REG_WPTR: begin wptr<=wr_data; wcount<=0; end
                    REG_WDATA: begin
                        weight_ram[wptr]<=wr_data;
                        wptr<=wptr+1; wcount<=wcount+1;
                    end
                    REG_BPTR: begin
                        bptr<=wr_data; bcount<=0; bias_low_valid<=0;
                    end
                    REG_BLO: begin
                        bias_low_latch<=wr_data; bias_low_valid<=1;
                    end
                    REG_BHI: begin
                        biases[bptr]<={wr_data,bias_low_latch};
                        bptr<=bptr+1; bcount<=bcount+1; bias_low_valid<=0;
                    end
                endcase
            end
        end
    end
endmodule
