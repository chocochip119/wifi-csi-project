`timescale 1ns / 1ps

// TB-only Loader placeholder. Public knobs are configured while idle.
// No blob parsing/RAM implementation or abort contract is invented here.
module loader_stub (
    input wire clk, resetn, loader_start,
    input wire [63:0] ld_data,
    input wire ld_valid,
    output wire ld_ready,
    output reg loader_done,
    output reg loader_err
);
    integer ready_mode = 0; // 0 always, 1 fixed, 2 repeated 8/2/1, 3 PRNG 0..8
    integer fixed_low_cycles = 8, done_delay_cycles = 0;
    integer expected_beats = 3722;
    reg [31:0] seed = 32'h13572468;
    bit inject_error = 0;
    reg [63:0] received [0:3721];
    integer received_count = 0, start_count = 0, done_count = 0;
    integer low_run = 0, max_low_run = 0, violations = 0;
    integer cooldown = 0, completion_wait = 0;
    bit active = 0, collecting = 0, completing = 0, held = 0, saved_error = 0;
    reg [63:0] held_data;
    reg [31:0] random_state;
    integer next_gap;
    assign ld_ready = resetn && collecting && cooldown == 0;

    function automatic [31:0] next_random(input reg [31:0] value);
        reg [31:0] x;
        begin
            x = value == 0 ? 32'd1 : value;
            x = x ^ (x << 13); x = x ^ (x >> 17);
            next_random = x ^ (x << 5);
        end
    endfunction

    task automatic fail(input string message);
        begin violations = violations+1; $fatal(1,"FAIL: loader_stub %s",message); end
    endtask

    always @(posedge clk) begin
        if (!resetn) begin
            loader_done <= 0; loader_err <= 0;
            active <= 0; collecting <= 0; completing <= 0;
            cooldown <= 0; completion_wait <= 0; received_count <= 0;
            start_count <= 0; done_count <= 0; held <= 0;
            low_run <= 0; max_low_run <= 0; random_state <= seed;
        end else begin
            loader_done <= 0; loader_err <= 0;
            if (held && (ld_valid !== 1'b1 || ld_data !== held_data))
                fail("VALID/data changed before stalled beat was accepted");
            held <= ld_valid && !ld_ready;
            held_data <= ld_data;
            if (collecting && !ld_ready) begin
                low_run <= low_run+1;
                if (low_run+1 > max_low_run) max_low_run <= low_run+1;
            end else low_run <= 0;
            if (cooldown > 0) cooldown <= cooldown-1;
            if (loader_start) begin
                if (active) fail("START received while non-idle");
                if (expected_beats < 1 || expected_beats > 3722 || fixed_low_cycles < 0 || done_delay_cycles < 0)
                    fail("invalid test configuration");
                active <= 1; collecting <= 1; completing <= 0;
                cooldown <= 0; received_count <= 0; saved_error <= inject_error;
                start_count <= start_count+1; random_state <= seed;
            end
            if (ld_valid && ld_ready) begin
                if (!active || received_count >= expected_beats) fail("more beats than expected");
                received[received_count] <= ld_data;
                received_count <= received_count+1;
                case (ready_mode)
                    0: next_gap = 0;
                    1: next_gap = fixed_low_cycles;
                    2: case (received_count % 3)
                        0: next_gap = 8;
                        1: next_gap = 2;
                        default: next_gap = 1;
                    endcase
                    3: begin
                        random_state <= next_random(random_state);
                        next_gap = int'(next_random(random_state) % 9);
                    end
                    default: begin next_gap = 0; fail("unknown ready_mode"); end
                endcase
                cooldown <= next_gap;
                if (received_count+1 == expected_beats) begin
                    collecting <= 0;
                    if (done_delay_cycles == 0) begin
                        loader_done <= 1; loader_err <= saved_error;
                        active <= 0; done_count <= done_count+1;
                    end else begin completing <= 1; completion_wait <= done_delay_cycles; end
                end
            end
            // Any additional offered beat is a producer contract error even
            // though READY is now low; do not silently hide an overrun.
            if (ld_valid && received_count >= expected_beats)
                fail("extra beat offered after complete payload");
            if (completing) begin
                if (completion_wait == 1) begin
                    completing <= 0; active <= 0;
                    loader_done <= 1; loader_err <= saved_error;
                    done_count <= done_count+1;
                end else completion_wait <= completion_wait-1;
            end
        end
    end
endmodule
