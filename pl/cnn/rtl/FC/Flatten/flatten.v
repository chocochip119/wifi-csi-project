`timescale 1ns / 1ps

module flatten (
    input  wire [8:0]  flat_raddr,
    output wire [63:0] flat_rdata,

    output wire [8:0]  feat_raddr,
    input  wire [63:0] feat_rdata
);

    assign feat_raddr = flat_raddr;
    assign flat_rdata = feat_rdata;

endmodule