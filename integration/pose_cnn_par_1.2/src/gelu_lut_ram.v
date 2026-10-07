`timescale 1 ns / 1 ps

// 05_Loader: one write address and one synchronous physical read port.
// No reset port: memory contents are never cleared by control reset.
// Concurrent read/write of the same address returns the previous value (read-first).
module gelu_lut_ram (
    input wire clk,
    input wire lut_we,
    input wire [9:0] lut_waddr,
    input wire [7:0] lut_wdata,
    input wire [9:0] enc_lut_raddr,
    output wire [7:0] enc_lut_rdata,
    input wire [9:0] fc_lut_raddr,
    output wire [7:0] fc_lut_rdata
);
    (* ram_style = "block" *) reg [7:0] mem [0:1023];
    // L-07 / D09: replace fixed encoder selection with FC-priority selection.
    // Both logical outputs currently broadcast the same physical read result.
    wire [9:0] read_addr = enc_lut_raddr;
    reg [7:0] read_data_reg;
    assign enc_lut_rdata = read_data_reg;
    assign fc_lut_rdata = read_data_reg;
    always @(posedge clk) begin
        if (lut_we) mem[lut_waddr] <= lut_wdata;
    end
    always @(posedge clk) begin
        read_data_reg <= mem[read_addr];
    end
endmodule
