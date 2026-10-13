`timescale 1ns/1ps
// Packed INT16 input features in a synchronous 32-bit BRAM.
module ridge_feature_mem #(parameter integer N_XWORDS=478)(
    input wire aclk, aresetn,
    input wire wr_ok, input wire [15:0] wr_addr, input wire [31:0] wr_data,
    input wire start_ok, input wire fetch, input wire [9:0] feature_idx,
    output reg [31:0] xptr, xcount, x_read_q
);
    localparam [15:0] REG_XPTR=16'h0020, REG_XDATA=16'h0024;
    (* ram_style = "block" *) reg [31:0] feature_ram [0:N_XWORDS-1];
    always @(posedge aclk) begin
        if (!aresetn) begin
            xptr<=0; xcount<=0; x_read_q<=0;
        end else begin
            if (fetch) x_read_q<=feature_ram[feature_idx[9:1]];
            if (wr_ok) begin
                case (wr_addr)
                    REG_XPTR: begin xptr<=wr_data; xcount<=0; end
                    REG_XDATA: begin
                        feature_ram[xptr]<=wr_data;
                        xptr<=xptr+1; xcount<=xcount+1;
                    end
                endcase
            end
            if (start_ok) xcount<=0;
        end
    end
endmodule
