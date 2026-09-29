`timescale 1 ns / 1 ps

// 05_Loader: one write address and one synchronous physical read port.
// No reset port: memory contents are never cleared by control reset.
// Concurrent read/write of the same address returns the previous value (read-first).
module param_ram (
    input wire clk,
    input wire param_we,
    input wire [8:0] param_waddr,
    input wire [95:0] param_wdata,
    input wire [2:0] param_wstrb,
    input wire [8:0] enc_param_raddr,
    output wire [95:0] enc_param_rdata,
    input wire [8:0] fc_param_raddr,
    output wire [95:0] fc_param_rdata
);
    (* ram_style = "block" *) reg [95:0] mem [0:327];
    // L-07 / D09: replace fixed encoder selection with FC-priority selection.
    // Both logical outputs currently broadcast the same physical read result.
    wire [8:0] read_addr = enc_param_raddr;
    reg [95:0] read_data_reg;
    assign enc_param_rdata = read_data_reg;
    assign fc_param_rdata = read_data_reg;
    always @(posedge clk) begin
        if (param_we && param_wstrb[0]) mem[param_waddr][31:0] <= param_wdata[31:0];
        if (param_we && param_wstrb[1]) mem[param_waddr][63:32] <= param_wdata[63:32];
        if (param_we && param_wstrb[2]) mem[param_waddr][95:64] <= param_wdata[95:64];
    end
    always @(posedge clk) begin
        read_data_reg <= mem[read_addr];
    end
endmodule
