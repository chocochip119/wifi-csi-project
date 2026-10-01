`timescale 1ns / 1ps

module pose_buffer #(
    parameter integer DATA_WIDTH = 8,
    parameter integer DEPTH      = 24,
    parameter integer ADDR_WIDTH = $clog2(DEPTH)
)(
    input  wire                      clk,
    input  wire                      rst_n,

    input  wire                      pose_we,
    input  wire [ADDR_WIDTH-1:0]     pose_waddr,
    input  wire [DATA_WIDTH-1:0]     pose_wdata,

    input  wire [ADDR_WIDTH-1:0]     pose_raddr,
    output reg  [DATA_WIDTH-1:0]     pose_rdata
);
    // Pose Memory
    reg [DATA_WIDTH-1:0] pose_mem [0:DEPTH-1];

    // Write
    always @(posedge clk) begin
        if (rst_n && pose_we)
            pose_mem[pose_waddr] <= pose_wdata;
    end

    // Synchronous Read
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pose_rdata <= 0;
        else
            pose_rdata <= pose_mem[pose_raddr];
    end

endmodule
