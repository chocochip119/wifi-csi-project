`timescale 1 ns / 1 ps

// 05_Loader r8-r31: resident Blob Decoder and four RAMs at the block boundary.
// Control reset is synchronous active-low; the RAM arrays have no reset.
module weight_param_loader (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         loader_start,
    output wire         loader_done,
    output wire         loader_err,
    input  wire [63:0]  ld_data,
    input  wire         ld_valid,
    output wire         ld_ready,
    output wire         cfg_ok,
    output wire [31:0]  pool_mult,
    output wire [31:0]  pool_shift,
    output wire [31:0]  output_scale_bits,
    input  wire         param_sel_fc,
    input  wire         lut_sel_fc,
    input  wire [8:0]   conv_raddr,
    output wire [127:0] conv_rdata,
    input  wire [8:0]   enc_param_raddr,
    output wire [95:0]  enc_param_rdata,
    input  wire [9:0]   enc_lut_raddr,
    output wire [7:0]   enc_lut_rdata,
    input  wire [8:0]   fc_param_raddr,
    output wire [95:0]  fc_param_rdata,
    input  wire [9:0]   fc_lut_raddr,
    output wire [7:0]   fc_lut_rdata,
    input  wire [11:0]  fcw_raddr,
    output wire [63:0]  fcw_rdata
);
    wire         conv_we;
    wire [8:0]   conv_waddr;
    wire [127:0] conv_wdata;
    wire [15:0]  conv_wstrb;
    wire         param_we;
    wire [8:0]   param_waddr;
    wire [95:0]  param_wdata;
    wire [2:0]   param_wstrb;
    wire         lut_we;
    wire [9:0]   lut_waddr;
    wire [7:0]   lut_wdata;
    wire         fcw_we;
    wire [11:0]  fcw_waddr;
    wire [63:0]  fcw_wdata;

    // D09 C: Top selects FC during FC1/FC2/FC3; otherwise selects Encoder.
    // Select addresses before the synchronous RAM, preserving one-cycle reads.
    // Encoder addresses may remain nonzero after enc_done; never combine them.
    wire [8:0] param_read_addr;
    wire [9:0] lut_read_addr;
    assign param_read_addr = param_sel_fc ? fc_param_raddr : enc_param_raddr;
    assign lut_read_addr = lut_sel_fc ? fc_lut_raddr : enc_lut_raddr;

    blob_decoder u_blob_decoder (
        .clk(clk), .rst_n(rst_n), .loader_start(loader_start),
        .loader_done(loader_done), .loader_err(loader_err),
        .ld_data(ld_data), .ld_valid(ld_valid), .ld_ready(ld_ready),
        .cfg_ok(cfg_ok), .pool_mult(pool_mult), .pool_shift(pool_shift),
        .output_scale_bits(output_scale_bits),
        .conv_we(conv_we), .conv_waddr(conv_waddr),
        .conv_wdata(conv_wdata), .conv_wstrb(conv_wstrb),
        .param_we(param_we), .param_waddr(param_waddr),
        .param_wdata(param_wdata), .param_wstrb(param_wstrb),
        .lut_we(lut_we), .lut_waddr(lut_waddr), .lut_wdata(lut_wdata),
        .fcw_we(fcw_we), .fcw_waddr(fcw_waddr), .fcw_wdata(fcw_wdata)
    );

    conv_weight_ram u_conv_weight_ram (
        .clk(clk), .conv_we(conv_we), .conv_waddr(conv_waddr),
        .conv_wdata(conv_wdata), .conv_wstrb(conv_wstrb),
        .conv_raddr(conv_raddr), .conv_rdata(conv_rdata)
    );

    // Existing RAMs broadcast one synchronous physical read result to both
    // logical outputs. Feed the selected address to both legacy address pins;
    // the upper mux owns selection, with no second RAM or extra pipeline stage.
    param_ram u_param_ram (
        .clk(clk), .param_we(param_we), .param_waddr(param_waddr),
        .param_wdata(param_wdata), .param_wstrb(param_wstrb),
        .enc_param_raddr(param_read_addr), .fc_param_raddr(param_read_addr),
        .enc_param_rdata(enc_param_rdata), .fc_param_rdata(fc_param_rdata)
    );

    gelu_lut_ram u_gelu_lut_ram (
        .clk(clk), .lut_we(lut_we), .lut_waddr(lut_waddr), .lut_wdata(lut_wdata),
        .enc_lut_raddr(lut_read_addr), .fc_lut_raddr(lut_read_addr),
        .enc_lut_rdata(enc_lut_rdata), .fc_lut_rdata(fc_lut_rdata)
    );

    fcw_ram u_fcw_ram (
        .clk(clk), .fcw_we(fcw_we), .fcw_waddr(fcw_waddr), .fcw_wdata(fcw_wdata),
        .fcw_raddr(fcw_raddr), .fcw_rdata(fcw_rdata)
    );
endmodule
