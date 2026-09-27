`timescale 1ns / 1ps

// 08_FC r95-r99: two 128-byte banks, byte write / synchronous 8-byte read.
// Addresses are local to the selected bank: waddr 0..127, raddr 0..15.
// Preserve specified port widths (8 / 5 bits); unused high bits must be zero.
// Invalid writes are ignored; invalid reads return zero without aliasing.
// Eight byte lanes allow one byte write and one 64-bit read.
// Same-edge read/write returns the OLD byte (read-first).
module hidden_buffer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        hidden_we,
    input  wire        hidden_wbank,
    input  wire [7:0]  hidden_waddr,
    input  wire [7:0]  hidden_wdata,
    input  wire        hidden_rbank,
    input  wire [4:0]  hidden_raddr,
    output reg  [63:0] hidden_rdata
);
    (* ram_style = "distributed" *) reg [7:0] lane0 [0:31];
    (* ram_style = "distributed" *) reg [7:0] lane1 [0:31];
    (* ram_style = "distributed" *) reg [7:0] lane2 [0:31];
    (* ram_style = "distributed" *) reg [7:0] lane3 [0:31];
    (* ram_style = "distributed" *) reg [7:0] lane4 [0:31];
    (* ram_style = "distributed" *) reg [7:0] lane5 [0:31];
    (* ram_style = "distributed" *) reg [7:0] lane6 [0:31];
    (* ram_style = "distributed" *) reg [7:0] lane7 [0:31];
    wire [4:0] write_word = {hidden_wbank, hidden_waddr[6:3]};
    wire [4:0] read_word = {hidden_rbank, hidden_raddr[3:0]};
    wire write_enable = rst_n && hidden_we && !hidden_waddr[7];

    always @(posedge clk) begin
        if (write_enable && hidden_waddr[2:0] == 3'd0) lane0[write_word] <= hidden_wdata;
        if (write_enable && hidden_waddr[2:0] == 3'd1) lane1[write_word] <= hidden_wdata;
        if (write_enable && hidden_waddr[2:0] == 3'd2) lane2[write_word] <= hidden_wdata;
        if (write_enable && hidden_waddr[2:0] == 3'd3) lane3[write_word] <= hidden_wdata;
        if (write_enable && hidden_waddr[2:0] == 3'd4) lane4[write_word] <= hidden_wdata;
        if (write_enable && hidden_waddr[2:0] == 3'd5) lane5[write_word] <= hidden_wdata;
        if (write_enable && hidden_waddr[2:0] == 3'd6) lane6[write_word] <= hidden_wdata;
        if (write_enable && hidden_waddr[2:0] == 3'd7) lane7[write_word] <= hidden_wdata;
    end

    // Storage is never reset. Only the read output register is cleared.
    // Keep RAM reads directly clocked to preserve fixed 1-cycle latency.
    always @(posedge clk) begin
        if (!rst_n)
            hidden_rdata <= 64'd0;
        else if (hidden_raddr[4])
            hidden_rdata <= 64'd0;
        else
            hidden_rdata <= {lane7[read_word], lane6[read_word],
                             lane5[read_word], lane4[read_word],
                             lane3[read_word], lane2[read_word],
                             lane1[read_word], lane0[read_word]};
    end
endmodule
