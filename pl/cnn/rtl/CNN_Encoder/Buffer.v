`timescale 1ns / 1ps

module Buffer #(
    parameter W_DATA_WIDTH = 64,
    parameter R_DATA_WIDTH = 8,
    parameter DEPTH_BYTE   = 11520,
    parameter W_ADDR_WIDTH = $clog2(DEPTH_BYTE * 8 / W_DATA_WIDTH),
    parameter R_ADDR_WIDTH = $clog2(DEPTH_BYTE * 8 / R_DATA_WIDTH)
) (
    input  wire                      clk,
    input  wire                      we,
    input  wire [W_ADDR_WIDTH - 1:0] waddr,
    input  wire [W_DATA_WIDTH - 1:0] wdata,
    input  wire [R_ADDR_WIDTH - 1:0] raddr,
    output reg  [R_DATA_WIDTH - 1:0] rdata
);

    localparam MIN_DATA_W = (W_DATA_WIDTH < R_DATA_WIDTH) ? W_DATA_WIDTH : R_DATA_WIDTH;
    localparam MAX_DATA_W = (W_DATA_WIDTH < R_DATA_WIDTH) ? R_DATA_WIDTH : W_DATA_WIDTH;
    localparam DEPTH = DEPTH_BYTE * 8 / MIN_DATA_W;
    localparam RATIO = MAX_DATA_W / MIN_DATA_W;

    generate
        // E-01: one full-word write, synchronous word read, and a lane selector
        // sampled on the SAME edge. Live raddr low bits would break latency.
        // Restrict this mapping to exact power-of-two ratios. Other parameter
        // combinations retain the original path and its simulation semantics.
        if ((W_DATA_WIDTH > R_DATA_WIDTH) &&
            ((W_DATA_WIDTH % R_DATA_WIDTH) == 0) &&
            ((RATIO & (RATIO - 1)) == 0)) begin : gen_word_write
            localparam DEPTH_W = DEPTH_BYTE * 8 / W_DATA_WIDTH;
            localparam LANE_BITS = $clog2(RATIO);
            reg [W_DATA_WIDTH - 1:0] mem [0:DEPTH_W - 1];
            reg [W_DATA_WIDTH - 1:0] read_word_reg;
            reg [LANE_BITS - 1:0] read_lane_reg;

            always @(posedge clk) begin
                if (we) mem[waddr] <= wdata;
                read_word_reg <= mem[raddr >> LANE_BITS];
                read_lane_reg <= raddr[LANE_BITS - 1:0];
            end
            // Nonblocking RAM read above returns pre-write data on a collision,
            // matching the original read-first behavior and little-endian lanes.
            always @(*) begin
                rdata = read_word_reg[read_lane_reg * R_DATA_WIDTH +: R_DATA_WIDTH];
            end
        end else begin : gen_legacy
            reg [MIN_DATA_W - 1:0] mem [0:DEPTH - 1];
            integer i;
            if (W_DATA_WIDTH >= R_DATA_WIDTH) begin : gen_wide_write
                always @(posedge clk) begin
                    if (we) begin
                        for (i = 0; i < RATIO; i = i + 1) mem[waddr * RATIO + i] <= wdata[i*MIN_DATA_W +: MIN_DATA_W];
                    end
                    rdata <= mem[raddr];
                end
            end else begin
                always @(posedge clk) begin : gen_wide_read
                    if (we) begin
                        mem[waddr] <= wdata;
                    end
                    for (i = 0; i < RATIO; i = i + 1) rdata[i*MIN_DATA_W +: MIN_DATA_W] <= mem[raddr * RATIO + i];
                end
            end
        end
    endgenerate

endmodule
