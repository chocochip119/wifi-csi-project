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

    reg [63:0] bank0 [0:15];
    reg [63:0] bank1 [0:15];

    wire [3:0] w_word = hidden_waddr[6:3];
    wire [2:0] w_byte = hidden_waddr[2:0];

    always @(posedge clk) begin
        if (rst_n && hidden_we) begin
            if (hidden_wbank == 1'b0) begin
                bank0[w_word][8*w_byte +: 8] <= hidden_wdata;
            end else begin
                bank1[w_word][8*w_byte +: 8] <= hidden_wdata;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            hidden_rdata <= 64'd0;
        end else begin
            if (hidden_rbank == 1'b0)
                hidden_rdata <= bank0[hidden_raddr];
            else
                hidden_rdata <= bank1[hidden_raddr];
        end
    end
endmodule
