`timescale 1ns / 1ps

// TB-only synchronous Encoder timing model. No CNN arithmetic is modeled.
module enc_stub (
    input wire clk, resetn, enc_start,
    output reg enc_done
);
    integer delay_cycles = 5;
    integer done_width_cycles = 1; // 0: hold until next accepted START/reset
    integer accepted_starts = 0, ignored_starts = 0, done_count = 0;
    integer cycle_count = 0, start_cycle = 0, done_cycle = 0;
    integer remaining = 0, width_left = 0;
    bit active = 0;
    reg prior_start;

    always @(posedge clk) begin
        if (!resetn) begin
            enc_done <= 0; active <= 0; remaining <= 0; width_left <= 0;
            accepted_starts <= 0; ignored_starts <= 0; done_count <= 0;
            cycle_count <= 0; start_cycle <= 0; done_cycle <= 0; prior_start <= 0;
        end else begin
            cycle_count <= cycle_count+1;
            if (enc_start && prior_start) $fatal(1,"FAIL: enc_stub START exceeds one cycle");
            prior_start <= enc_start;
            if (enc_done && done_width_cycles != 0) begin
                if (width_left <= 1) enc_done <= 0;
                else width_left <= width_left-1;
            end
            if (enc_start && active) begin
                // Actual Encoder Q3 behavior: record and ignore, do not restart.
                ignored_starts <= ignored_starts+1;
            end
            if (enc_start && !active) begin
                if (delay_cycles < 0 || done_width_cycles < 0)
                    $fatal(1,"FAIL: enc_stub invalid delay/width");
                accepted_starts <= accepted_starts+1;
                start_cycle <= cycle_count;
                enc_done <= 0;
                if (delay_cycles == 0) begin
                    // Earliest synchronous completion: after START's sampling edge.
                    enc_done <= 1; width_left <= done_width_cycles;
                    done_count <= done_count+1; done_cycle <= cycle_count;
                end else begin active <= 1; remaining <= delay_cycles; end
            end else if (active) begin
                if (remaining == 1) begin
                    active <= 0; enc_done <= 1; width_left <= done_width_cycles;
                    done_count <= done_count+1; done_cycle <= cycle_count;
                end else remaining <= remaining-1;
            end
        end
    end
endmodule
