`timescale 1ns/1ps
module tb_pose_rx5_golden;
  reg clk=0,rst_n=0,start=0,clear=0;
  always #5 clk=~clk;
  reg [31:0] cmd=1;
  wire busy,done,cfg;
  wire [3:0] err;
  wire [31:0] scale,rd_addr,wr_addr;
  wire rd_start,rd_ready,wr_start;
  wire [19:0] rd_bytes,wr_bytes;
  reg rd_busy=0,wr_busy=0;
  wire [63:0] rd_data,wr_data;
  wire rd_valid=rd_busy;
  wire wr_ready=wr_busy;
  reg [7:0] blob[0:685135],inp[0:19199],expected[0:23],actual[0:23];
  integer rpos=0,rleft=0,wpos=0,wleft=0,cycle=0,fd,i,j,n,errors=0,wr_count=0;
  reg [63:0] rbeat;
  assign rd_data=rbeat;
  // ROM contents are loaded once before the first DMA command. Avoid adding
  // 704k byte-array words to the simulator's combinational sensitivity list.
  always @(rpos) begin
    rbeat=0;
    for(integer b=0;b<8;b=b+1) begin
      if(rpos>=32'h10000000 && rpos<32'h10000000+685136) rbeat[8*b+:8]=blob[rpos-32'h10000000+b];
      else if(rpos>=32'h20000000 && rpos<32'h20000000+19200) rbeat[8*b+:8]=inp[rpos-32'h20000000+b];
    end
  end
  pose_cnn #(.RX(5)) dut(
    .clk(clk),.rst_n(rst_n),.reg_start(start),.reg_clear_status(clear),.reg_cmd(cmd),
    .reg_input_addr(32'h20000000),.reg_weight_addr(32'h10000000),.reg_output_addr(32'h30000000),
    .status_busy(busy),.status_done(done),.status_error(err),.cfg_ok(cfg),.output_scale_bits(scale),
    .mem_rd_start(rd_start),.mem_rd_addr(rd_addr),.mem_rd_bytes(rd_bytes),.mem_rd_busy(rd_busy),
    .mem_rd_data(rd_data),.mem_rd_valid(rd_valid),.mem_rd_ready(rd_ready),.mem_rd_err(1'b0),
    .mem_wr_start(wr_start),.mem_wr_addr(wr_addr),.mem_wr_bytes(wr_bytes),.mem_wr_busy(wr_busy),
    .mem_wr_data(wr_data),.mem_wr_ready(wr_ready),.mem_wr_err(1'b0));
  always @(posedge clk) begin
    cycle<=cycle+1;
    if(cycle % 500000 == 0) $display("PROGRESS cycle=%0d ctrl=%0d rd_busy=%b rd_addr=%h",cycle,dut.u_ctrl.state_reg,rd_busy,rpos);
    if(rd_start) begin rd_busy<=1;rpos<=rd_addr;rleft<=rd_bytes;end
    else if(rd_busy && rd_ready) begin rpos<=rpos+8;rleft<=rleft-8;if(rleft==8)rd_busy<=0;end
    if(wr_start) begin
      if(wr_addr != 32'h30000000 || wr_bytes != 24) $fatal(1,"invalid output DMA");
      wr_busy<=1;wpos<=0;wleft<=wr_bytes;end
    else if(wr_busy) begin
      for(integer b=0;b<8;b=b+1)actual[wpos+b]<=wr_data[8*b+:8];
      wpos<=wpos+8;wleft<=wleft-8;wr_count<=wr_count+1;if(wleft==8)wr_busy<=0;
    end
  end
  task launch(input [31:0] c);
    begin @(negedge clk);cmd=c;start=1;@(negedge clk);start=0;
      wait(busy);wait(!busy);@(negedge clk);
      if(!done || err)$fatal(1,"command %0d failed cfg=%b err=%0d cycle=%0d",c,cfg,err,cycle);
    end
  endtask
  initial begin
    fd=$fopen("weights_5rx.bin","rb");n=$fread(blob,fd);$fclose(fd);if(n!=685136)$fatal;
    fd=$fopen("golden_input.bin","rb");n=$fread(inp,fd);$fclose(fd);if(n!=19200)$fatal;
    fd=$fopen("golden_pose.bin","rb");n=$fread(expected,fd);$fclose(fd);if(n!=24)$fatal;
    repeat(5)@(negedge clk);rst_n=1;launch(1);
    if(scale !== {blob[19],blob[18],blob[17],blob[16]}) $fatal(1,"output scale mismatch");
    $display("LOAD PASS scale=%h cycles=%0d",scale,cycle);
    for(j=0;j<2;j=j+1)begin
      launch(0);
      if(wr_count != (j+1)*3) $fatal(1,"output beat count mismatch");
      for(i=0;i<24;i=i+1)if(actual[i]!==expected[i])begin errors=errors+1;$display("MISMATCH %0d got=%0d exp=%0d",i,$signed(actual[i]),$signed(expected[i]));end
      $display("INFER run=%0d errors=%0d cycles=%0d writes=%0d",j,errors,cycle,wr_count);
    end
    if(errors)$fatal(1,"full output mismatch");
    $display("FULL RX5 PASS: two inferences 24/24 bytes each");$finish;
  end
  initial begin #100000000; $fatal(1,"TIMEOUT cycle=%0d",cycle);end
endmodule
