`timescale 1ns / 1ps

module fc_fifo #(
    parameter integer DATA_WIDTH = 64,
    parameter integer DEPTH      = 512
)(
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire                     fifo_we,
    input  wire [DATA_WIDTH-1:0]    fifo_wdata,
    output wire                     fifo_full,

    input  wire                     fifo_re,
    output wire [DATA_WIDTH-1:0]    fifo_rdata,
    output wire                     fifo_empty
);
    // Pointer / Counter Width
    localparam integer PTR_WIDTH = $clog2(DEPTH);
    localparam integer CNT_WIDTH = $clog2(DEPTH + 1);

    // FIFO Memory
    reg [DATA_WIDTH-1:0] ram [0:DEPTH-1];

    // Pointer / Counter
    reg [PTR_WIDTH-1:0] wr_ptr;
    reg [PTR_WIDTH-1:0] rd_ptr;
    reg [CNT_WIDTH-1:0] count;

    // FWFT Head
    reg [DATA_WIDTH-1:0] head_data;

    // Push / Pop Control
    wire push = fifo_we && !fifo_full;
    wire pop  = fifo_re && !fifo_empty;

    wire write_head;
    wire write_ram;
    wire read_ram;

    assign fifo_empty = (count == 0);
    assign fifo_full  = (count == DEPTH);

    assign write_head = push && (count == 0 || (pop && count == 1));
    assign write_ram  = push && !write_head;
    assign read_ram   = pop && (count > 1);

    assign fifo_rdata = head_data;

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr    <= 0;
            rd_ptr    <= 0;
            count     <= 0;
            head_data <= 0;
        end else begin
            // Write Pointer
            if (write_ram) begin
                if (wr_ptr == DEPTH - 1)
                    wr_ptr <= 0;
                else
                    wr_ptr <= wr_ptr + 1'b1;
            end

            // Read Pointer
            if (read_ram) begin
                if (rd_ptr == DEPTH - 1)
                    rd_ptr <= 0;
                else
                    rd_ptr <= rd_ptr + 1'b1;
            end

            // Word Counter
            case ({push, pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase

            // FWFT Head Control
            if (push && count == 0)
                head_data <= fifo_wdata;
            else if (push && pop && count == 1)
                head_data <= fifo_wdata;
            else if (read_ram)
                head_data <= ram[rd_ptr];
        end
    end

    // FIFO RAM Write
    always @(posedge clk) begin
        if (rst_n && write_ram)
            ram[wr_ptr] <= fifo_wdata;
    end

endmodule
