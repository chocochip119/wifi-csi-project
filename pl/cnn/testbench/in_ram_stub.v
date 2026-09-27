`timescale 1ns / 1ps

// TB-only input RAM and independent address/sequence checker.
module in_ram_stub (
    input wire clk, resetn, in_we,
    input wire [10:0] in_waddr,
    input wire [63:0] in_wdata
);
    reg [63:0] mem [0:1439];
    reg [10:0] address_log [0:1439];
    reg [63:0] data_log [0:1439];
    integer cycle_log [0:1439];
    reg [1439:0] written;
    integer write_count = 0, cycle_count = 0, violations = 0;

    // Start a new observation window while idle. RAM contents are not cleared.
    // The test calls this on a falling edge, before each inference.
    task begin_transfer;
        begin written = '0; write_count = 0; end
    endtask
    task automatic fail(input string message);
        begin violations = violations+1; $fatal(1,"FAIL: in_ram_stub %s",message); end
    endtask

    always @(posedge clk) begin
        if (!resetn) begin
            written <= '0; write_count <= 0; cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count+1;
            if (in_we !== 1'b0 && in_we !== 1'b1) fail("unknown write enable");
            if (in_we) begin
                if ((^in_waddr) === 1'bx) fail("unknown write address");
                // 1,440 words have legal indices 0..1,439; 1,440 is invalid.
                if (in_waddr >= 1440) fail("address outside 0..1439");
                if (written[in_waddr]) fail("duplicate address");
                if (int'(in_waddr) != write_count) fail("address must increase by exactly one from zero");
                if ((^in_wdata) === 1'bx) fail("unknown write data");
                mem[in_waddr] <= in_wdata;
                address_log[write_count] <= in_waddr;
                data_log[write_count] <= in_wdata;
                cycle_log[write_count] <= cycle_count;
                written[in_waddr] <= 1'b1;
                write_count <= write_count+1;
            end
        end
    end
endmodule
