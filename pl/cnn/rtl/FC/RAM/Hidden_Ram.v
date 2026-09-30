`timescale 1ns / 1ps

module hidden_ram (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        hidden_we,
    input  wire        hidden_wbank,
    input  wire [6:0]  hidden_waddr,
    input  wire [7:0]  hidden_wdata,

    input  wire        hidden_rbank,
    input  wire [3:0]  hidden_raddr,
    output reg  [63:0] hidden_rdata
);
    // 128 Byte / Bank
    reg [63:0] bank0 [0:15];
    reg [63:0] bank1 [0:15];

    wire [3:0] w_word = hidden_waddr[6:3];
    wire [2:0] w_byte = hidden_waddr[2:0];

    // 8-bit Write
    always @(posedge clk) begin
        if (rst_n && hidden_we) begin
            if (!hidden_wbank)
                bank0[w_word][8*w_byte +: 8] <= hidden_wdata;
            else
                bank1[w_word][8*w_byte +: 8] <= hidden_wdata;
        end
    end

    // 64-bit Synchronous Read
    always @(posedge clk) begin
        if (!rst_n) begin
            hidden_rdata <= 64'd0;
        end else begin
            if (!hidden_rbank)
                hidden_rdata <= bank0[hidden_raddr];
            else
                hidden_rdata <= bank1[hidden_raddr];
        end
    end

endmodule
