`timescale 1 ns / 1 ps

// 05_Loader: one write address and one synchronous physical read port.
// No reset port: memory contents are never cleared by control reset.
// Concurrent read/write of the same address returns the previous value (read-first).
module conv_weight_ram (
    input wire clk,
    input wire conv_we,
    input wire [8:0] conv_waddr,
    input wire [127:0] conv_wdata,
    input wire [15:0] conv_wstrb,
    input wire [8:0] conv_raddr,
    output reg [127:0] conv_rdata
);
    (* ram_style = "block" *) reg [127:0] mem [0:332];
    always @(posedge clk) begin
        if (conv_we && conv_wstrb[0]) mem[conv_waddr][7:0] <= conv_wdata[7:0];
        if (conv_we && conv_wstrb[1]) mem[conv_waddr][15:8] <= conv_wdata[15:8];
        if (conv_we && conv_wstrb[2]) mem[conv_waddr][23:16] <= conv_wdata[23:16];
        if (conv_we && conv_wstrb[3]) mem[conv_waddr][31:24] <= conv_wdata[31:24];
        if (conv_we && conv_wstrb[4]) mem[conv_waddr][39:32] <= conv_wdata[39:32];
        if (conv_we && conv_wstrb[5]) mem[conv_waddr][47:40] <= conv_wdata[47:40];
        if (conv_we && conv_wstrb[6]) mem[conv_waddr][55:48] <= conv_wdata[55:48];
        if (conv_we && conv_wstrb[7]) mem[conv_waddr][63:56] <= conv_wdata[63:56];
        if (conv_we && conv_wstrb[8]) mem[conv_waddr][71:64] <= conv_wdata[71:64];
        if (conv_we && conv_wstrb[9]) mem[conv_waddr][79:72] <= conv_wdata[79:72];
        if (conv_we && conv_wstrb[10]) mem[conv_waddr][87:80] <= conv_wdata[87:80];
        if (conv_we && conv_wstrb[11]) mem[conv_waddr][95:88] <= conv_wdata[95:88];
        if (conv_we && conv_wstrb[12]) mem[conv_waddr][103:96] <= conv_wdata[103:96];
        if (conv_we && conv_wstrb[13]) mem[conv_waddr][111:104] <= conv_wdata[111:104];
        if (conv_we && conv_wstrb[14]) mem[conv_waddr][119:112] <= conv_wdata[119:112];
        if (conv_we && conv_wstrb[15]) mem[conv_waddr][127:120] <= conv_wdata[127:120];
    end
    always @(posedge clk) begin
        conv_rdata <= mem[conv_raddr];
    end
endmodule
