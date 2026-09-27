`timescale 1ns / 1ps

// 08_FC r106-r109: one byte write per edge, 24-byte parallel output.
// Byte k occupies pose_data[8*k +: 8]. Unwritten bytes retain their values.
// Storage is not reset. F-03 controls when a complete pose is valid.
module pose_buffer (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         pose_we,
    input  wire [4:0]   pose_waddr,
    input  wire [7:0]   pose_wdata,
    output wire [191:0] pose_data
);
    reg [7:0] mem [0:23];
    always @(posedge clk) begin
        if (rst_n && pose_we && pose_waddr < 5'd24)
            mem[pose_waddr] <= pose_wdata;
    end
    assign pose_data = {mem[23], mem[22], mem[21], mem[20],
                        mem[19], mem[18], mem[17], mem[16],
                        mem[15], mem[14], mem[13], mem[12],
                        mem[11], mem[10], mem[9],  mem[8],
                        mem[7],  mem[6],  mem[5],  mem[4],
                        mem[3],  mem[2],  mem[1],  mem[0]};
endmodule
