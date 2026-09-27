`timescale 1ns / 1ps

// Compile with tb_m00_read.v for its fixture; elaborate ONLY this top to run
// performance independently. Optional +LATENCY=0/16/32/64 selects one point.
// No wave logging. 128-byte-aligned baseline matches the requested 3072 bursts.
module tb_m00_read_perf;
    m00_read_fixture env();
    integer selected_latency;
    real cycles_per_beat, time_us;
    string judgement;
    task automatic measure(input integer latency);
        begin
            env.memory.ddr_latency_cycles = latency;
            env.run_read($sformatf("fc1_latency_%0d", latency), 32'h1e100000,
                         393216, 32'hfc100001, 3072, 0, 0);
            env.check(env.held_valid_cycles == 0 && env.ar_stall_cycles == 0, "performance has no consumer/address stalls");
            env.check(env.total_cycles == env.word_count+env.inter_burst_idle+env.startup_idle,
                      "cycle ledger = data + between-burst idle + initial idle");
            cycles_per_beat = real'(env.total_cycles)/49152.0;
            time_us = real'(env.total_cycles)*0.01; // 100 MHz = 10 ns/clock.
            if (cycles_per_beat < 1.2) judgement = "one_outstanding_sufficient_under_this_latency";
            else if (cycles_per_beat > 1.5) judgement = "review_2_to_4_outstanding";
            else judgement = "between_thresholds_no_predefined_decision";
            $display("PERF: latency=%0d bytes=393216 beats=%0d bursts=%0d cycles=%0d cycles_per_beat=%0.6f inter_burst_idle=%0d startup_idle=%0d time_us_100mhz=%0.2f judgement=%s",
                     latency, env.word_count, env.ar_count, env.total_cycles, cycles_per_beat,
                     env.inter_burst_idle, env.startup_idle, time_us, judgement);
        end
    endtask
    initial begin #100000000; $fatal(1, "FAIL: performance TB global timeout"); end
    initial begin
        env.reset_fixture;
        if ($value$plusargs("LATENCY=%d", selected_latency)) begin
            env.check(selected_latency == 0 || selected_latency == 16 || selected_latency == 32 || selected_latency == 64,
                      "latency must be one of the four requested sweep points");
            measure(selected_latency);
        end else begin
            measure(0); measure(16); measure(32); measure(64);
        end
        env.close_fixture;
        $display("PASS: T-02b PERFORMANCE MEASUREMENT COMPLETE; all words checked, C11 enabled, violations=0");
        $finish;
    end
endmodule
