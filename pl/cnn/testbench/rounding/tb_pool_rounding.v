`timescale 1ns/1ps
module tb_pool_rounding;
    reg clk=0;
    always #5 clk=~clk;
    reg [31:0] shift=0;
    reg signed [47:0] product=0;
    reg signed [14:0] dividend=0;
    integer p, expected, actual, magnitude, s;
    Pool dut(.clk(clk),.rst_n(1'b0),.pool_q(8'd0),.pool_valid(1'b0),.pool_tag(19'd0),
             .pool_mult(32'd1),.pool_shift(shift),.feat_raddr(9'd0),.feat_rdata(),.enc_done());
    initial begin
        force dut.prod_r2 = product;
        force dut.p_r4 = dividend;
        for(p=-8191;p<=8191;p=p+1) begin
            dividend=p;
            #1;
            dut.dq_r5=dut.dq;
            dut.neg_r5=dut.pp[16];
            #1;
            magnitude=(p<0 ? -p : p);
            expected=(magnitude+24)/48;
            if(expected>127) expected=127;
            if(p<0) expected=-expected;
            actual=$signed(dut.q_clamp);
            if(actual != expected) $fatal(1,"Pool /48 mismatch %0d got=%0d exp=%0d",p,actual,expected);
        end
        for(s=0;s<=49;s=s+1) begin
            shift=s;
            for(p=-129;p<=129;p=p+1) begin
                product=p;
                #1;
                magnitude=(p<0 ? -p : p);
                if(s==0) expected=p;
                else if(s>=9) expected=0;
                else begin
                    expected=(magnitude+(1<<(s-1)))>>s;
                    if(p<0) expected=-expected;
                end
                if($signed(dut.rs) != expected) $fatal(1,"Pool shift mismatch p=%0d shift=%0d",p,s);
            end
        end
        $display("PASS Pool /48 exhaustive=16383; shift cases=12950");
        $finish;
    end
endmodule
