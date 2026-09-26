`timescale 1ns / 1ps

module fc_fifo #(
    parameter integer DATA_WIDTH = 64,
    parameter integer DEPTH      = 512
)(
    input wire                     clk,
    input wire                     rst_n,
            
    input wire                     fifo_we,
    input wire [DATA_WIDTH-1 : 0]  fifo_wdata,
    output wire                    fifo_full,
                
    input wire                     fifo_re,
    output wire [DATA_WIDTH-1 : 0] fifo_rdata,
    output wire                    fifo_empty
    );
    // Pointer / Counter Width
    localparam integer PTR_WIDTH = $clog2(DEPTH);
    localparam integer CNT_WIDTH = $clog2(DEPTH + 1);

    // FIFO Memory
    reg [DATA_WIDTH-1:0] ram [0:DEPTH-1];

    // Write / Read Pointer
    reg [PTR_WIDTH-1:0] wr_ptr, rd_ptr;
    // FIFO Word Counter
    reg [CNT_WIDTH-1:0] count;
    // FWFT Output Register
    reg [DATA_WIDTH-1:0] head_data;
    // Push / Pop Control
    wire push = fifo_we && !fifo_full;
    wire pop  = fifo_re && !fifo_empty;

    assign fifo_empty = (count == 0);
    assign fifo_full  = (count == DEPTH);

    wire write_head;
    wire write_ram;
    wire read_ram;

    assign write_head = push && (count == 0 || (pop && count == 1));
    assign write_ram  = push && !write_head;
    assign read_ram   = pop && (count > 1);

    assign fifo_rdata = head_data;

    always @(posedge clk) begin
        if(!rst_n)begin
            wr_ptr    <= 0;
            rd_ptr    <= 0;
            count     <= 0;
            head_data <= 0;
        end else begin
            // write pointer
            if (write_ram) begin
                if (wr_ptr == DEPTH -1)begin
                   wr_ptr <= 0; 
                end else begin
                   wr_ptr <= wr_ptr + 1'b1;
                end
            end
            // read pointer
            if (read_ram) begin
                if (rd_ptr == DEPTH - 1) begin
                    rd_ptr <= 0;
                end else begin
                    rd_ptr <= rd_ptr + 1'b1;
                end
            end
            // count
            case ({push, pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
            // FWFT Head Control
            if (push && (count == 0)) begin
                head_data <= fifo_wdata;
            end else if (push && pop && (count == 1)) begin
                head_data <= fifo_wdata;
            end else if (read_ram) begin
                head_data <= ram[rd_ptr];
            end
        end
    end
    // FIFO RAM Write
    always @(posedge clk) begin
        if (rst_n && write_ram) begin
            ram[wr_ptr] <= fifo_wdata;
        end
    end

endmodule
