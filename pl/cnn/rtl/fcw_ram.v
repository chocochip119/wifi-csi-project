`timescale 1 ns / 1 ps

// 05_Loader: one write address and one synchronous physical read port.
// No reset port: memory contents are never cleared by control reset.
// Concurrent read/write of the same address returns the previous value (read-first).
module fcw_ram (
    input wire clk,
    input wire fcw_we,
    input wire [11:0] fcw_waddr,
    input wire [63:0] fcw_wdata,
    input wire [11:0] fcw_raddr,
    output reg [63:0] fcw_rdata
);
    (* ram_style = "block" *) reg [63:0] mem [0:2431];
    always @(posedge clk) begin
        if (fcw_we) mem[fcw_waddr] <= fcw_wdata;
    end
    always @(posedge clk) begin
        fcw_rdata <= mem[fcw_raddr];
    end
endmodule
