`timescale 1ns / 1ps

module flatten #(
    parameter integer RX_NUM       = 3,
    parameter integer WORDS_PER_RX = 128,
    parameter integer FLAT_WORDS   = RX_NUM * WORDS_PER_RX,
    parameter integer ADDR_WIDTH   = $clog2(FLAT_WORDS)
)(
    input  wire [ADDR_WIDTH-1:0] flat_raddr,
    output wire [63:0]           flat_rdata,

    output wire [ADDR_WIDTH-1:0] feat_raddr,
    input  wire [63:0]           feat_rdata
);
    // Address Pass-Through
    assign feat_raddr = flat_raddr;
    assign flat_rdata = feat_rdata;

endmodule
