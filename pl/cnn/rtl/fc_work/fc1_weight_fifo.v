`timescale 1ns / 1ps

// 08_FC r26/r31-r36: 512 x 64, FWFT, single clock.
// Full always rejects a write, including a simultaneous pop (512 -> 511).
// Top must obey fifo_full; there is no ready or overflow output.
module fc1_weight_fifo (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        fifo_we,
    input  wire [63:0] fifo_wdata,
    output wire        fifo_full,
    input  wire        fifo_re,
    output wire [63:0] fifo_rdata,
    output wire        fifo_empty
);
    (* ram_style = "block" *) reg [63:0] mem [0:511];
    reg [8:0] write_ptr_reg, write_ptr_next;
    reg [8:0] read_ptr_reg, read_ptr_next;
    reg [9:0] count_reg, count_next;
    reg bypass_reg, bypass_next;
    reg [63:0] ram_head_reg;
    reg [63:0] bypass_data_reg;

    assign fifo_full  = (count_reg == 10'd512);
    assign fifo_empty = (count_reg == 10'd0);
    wire push = fifo_we && !fifo_full;
    wire pop  = fifo_re && !fifo_empty;
    wire [8:0] following_addr = read_ptr_reg + 9'd1;
    wire load_bypass = push && (fifo_empty || (pop && count_reg == 10'd1));
    wire read_following = pop && (count_reg > 10'd1);

    // RAM head and bypass are cached copies, not extra FIFO capacity.
    // On a pop, fetch the following word at that same edge. It is available
    // as the new head immediately afterwards, including consecutive pops.
    // An empty push or single-word replacement bypasses the RAM read latency
    // and avoids relying on a same-address RAM read/write collision mode.
    assign fifo_rdata = bypass_reg ? bypass_data_reg : ram_head_reg;

    always @(*) begin
        write_ptr_next = write_ptr_reg;
        read_ptr_next = read_ptr_reg;
        count_next = count_reg;
        bypass_next = bypass_reg;
        if (push)
            write_ptr_next = write_ptr_reg + 9'd1;
        if (pop)
            read_ptr_next = following_addr;
        case ({push, pop})
            2'b10: count_next = count_reg + 10'd1;
            2'b01: count_next = count_reg - 10'd1;
            default: count_next = count_reg;
        endcase
        if (load_bypass)
            bypass_next = 1'b1;
        else if (read_following)
            bypass_next = 1'b0;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            write_ptr_reg <= 9'd0;
            read_ptr_reg <= 9'd0;
            count_reg <= 10'd0;
            bypass_reg <= 1'b0;
        end else begin
            write_ptr_reg <= write_ptr_next;
            read_ptr_reg <= read_ptr_next;
            count_reg <= count_next;
            bypass_reg <= bypass_next;
        end
    end

    // No reset on the array or cached data. fifo_empty masks their validity.
    // Exactly one RAM write address and one synchronous RAM read address.
    always @(posedge clk) begin
        if (rst_n && push)
            mem[write_ptr_reg] <= fifo_wdata;
        if (rst_n && read_following)
            ram_head_reg <= mem[following_addr];
    end
    always @(posedge clk) begin
        if (rst_n && load_bypass)
            bypass_data_reg <= fifo_wdata;
    end
endmodule
