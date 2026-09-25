
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

    reg [MIN_DATA_W - 1:0] mem[0:DEPTH - 1];
    integer i;

    generate
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
    endgenerate

endmodule
