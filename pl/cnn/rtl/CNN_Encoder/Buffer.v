`timescale 1ns/1ps

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
    localparam LOG2_RATIO = (RATIO > 1) ? $clog2(RATIO) : 1;

    // ------------------------------------------------------------
    // 수정 전 코드 : 합성 실패
    // mem[waddr * RATIO + i] 형태는 Vivado가 "임의 주소 RATIO개에 동시 쓰기(쓰기 포트 RATIO개)"로 보고
    // BRAM 추론 불가 → [Synth 8-3391] Unable to infer a block/distributed RAM
    // ------------------------------------------------------------
    /*
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
    */

    // ------------------------------------------------------------
    // 수정 코드 : UG901 asymmetric RAM template
    // 넓은 쪽 주소를 {addr, lsb} 로 이어 붙여야 "넓은 word 한 줄 쓰기/읽기"로 인식 → BRAM 포트 폭 설정
    // (RATIO 는 2의 거듭제곱)
    // ------------------------------------------------------------
    reg [MIN_DATA_W - 1:0] mem[0:DEPTH - 1];

    generate
        if (RATIO == 1) begin : gen_same_width
            always @(posedge clk) begin
                if (we) mem[waddr] <= wdata;
            end
            always @(posedge clk) begin
                rdata <= mem[raddr];
            end
        end else if (W_DATA_WIDTH > R_DATA_WIDTH) begin : gen_wide_write
            always @(posedge clk) begin : write_wide
                integer i;
                reg [LOG2_RATIO - 1:0] lsb;
                for (i = 0; i < RATIO; i = i + 1) begin
                    lsb = i;
                    if (we) mem[{waddr, lsb}] <= wdata[i*MIN_DATA_W +: MIN_DATA_W];
                end
            end
            always @(posedge clk) begin
                rdata <= mem[raddr];
            end
        end else begin : gen_wide_read
            always @(posedge clk) begin
                if (we) mem[waddr] <= wdata;
            end
            always @(posedge clk) begin : read_wide
                integer i;
                reg [LOG2_RATIO - 1:0] lsb;
                for (i = 0; i < RATIO; i = i + 1) begin
                    lsb = i;
                    rdata[i*MIN_DATA_W +: MIN_DATA_W] <= mem[{raddr, lsb}];
                end
            end
        end
    endgenerate

endmodule
