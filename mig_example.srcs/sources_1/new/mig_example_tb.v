`timescale 1ns/1ns

module mig_example_tb();

    reg clk, clk_100mhz, rst_n;
    wire[15:0] LED;
    reg[15:0] SW;

    defparam cpu.imem.INIT_FILE = "/home/christopher/git/raisin64-cpu/support/imem.hex";
    //defparam cpu.dmem.INIT_FILE = "/home/christopher/git/raisin64-cpu/support/dmem.hex";

    //////  DDR2 Model  //////
    wire ddr2_ck_p, ddr2_ck_n, ddr2_cke, ddr2_cs_n, ddr2_ras_n, ddr2_cas_n, ddr2_we_n, ddr2_odt;
    wire[15:0] ddr2_dq;
    wire[1:0] ddr2_dqs_n;
    wire[1:0] ddr2_dqs_p;
    wire[12:0] ddr2_addr;
    wire[2:0] ddr2_ba;
    wire[1:0] ddr2_dm;

    ddr2_model fake_ddr2(
        .ck(ddr2_ck_p),
        .ck_n(ddr2_ck_n),
        .cke(ddr2_cke),
        .cs_n(ddr2_cs_n),
        .ras_n(ddr2_ras_n),
        .cas_n(ddr2_cas_n),
        .we_n(ddr2_we_n),
        .dm_rdqs(ddr2_dm),
        .ba(ddr2_ba),
        .addr(ddr2_addr),
        .dq(ddr2_dq),
        .dqs(ddr2_dqs_p),
        .dqs_n(ddr2_dqs_n),
        .rdqs_n(),
        .odt(ddr2_odt)
        );

    //////////  DUT  //////////
    wire[63:0] mem_from_cpu;
    wire[63:0] mem_to_cpu;
    wire[63:0] mem_addr;
    wire mem_addr_valid;
    wire mem_from_cpu_write;
    wire mem_to_cpu_ready;

    raisin64 cpu(
        .clk(clk),
        .clk_100mhz(clk_100mhz),
        .rst_n(rst_n),
        .mem_din(mem_to_cpu),
        .mem_dout(mem_from_cpu),
        .mem_addr(mem_addr),
        .mem_addr_valid(mem_addr_valid),
        .mem_dout_write(mem_from_cpu_write),
        .mem_din_ready(mem_to_cpu_ready),

        .ddr2_addr(ddr2_addr),
        .ddr2_ba(ddr2_ba),
        .ddr2_cas_n(ddr2_cas_n),
        .ddr2_ck_n(ddr2_ck_n),
        .ddr2_ck_p(ddr2_ck_p),
        .ddr2_cke(ddr2_cke),
        .ddr2_ras_n(ddr2_ras_n),
        .ddr2_we_n(ddr2_we_n),
        .ddr2_dq(ddr2_dq),
        .ddr2_dqs_n(ddr2_dqs_n),
        .ddr2_dqs_p(ddr2_dqs_p),
        .ddr2_cs_n(ddr2_cs_n),
        .ddr2_dm(ddr2_dm),
        .ddr2_odt(ddr2_odt),

        .jtag_tck(1'b0),
        .jtag_tms(1'b0),
        .jtag_tdi(1'b0),
        .jtag_trst(1'b0)
        );

    //////////  IO  //////////
    wire led_en, sw_en, vga_en;
    memory_map memory_map_external(
        .addr(mem_addr_valid ? mem_addr : 64'h0),
        .led(led_en),
        .sw(sw_en),
        .vga(vga_en)
        );

    //As noted in raisin64.v because our IO architecture will need to be completely
    //re-written with the introduction of caches, we only support 64-bit aligned
    //access to IO space for now.
    reg[15:0] led_reg;
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n) led_reg <= 16'h0;
        else if(led_en & mem_addr_valid & mem_from_cpu_write) led_reg <= mem_from_cpu;
    end

    assign LED = led_reg;


    //SW uses a small synchronizer
    reg[15:0] sw_pre0, sw_pre1;
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            sw_pre0 <= 16'h0;
            sw_pre1 <= 16'h0;
        end else begin
            sw_pre0 <= sw_pre1;
            sw_pre1 <= SW;
        end
    end

    //Data selection
    assign mem_to_cpu_ready = mem_addr_valid;
    assign mem_to_cpu = sw_en ? sw_pre0 :
                        64'h0;

    initial begin
        clk = 1;
        forever #9 clk = ~clk;
    end

    initial begin
        clk_100mhz = 1;
        forever #5 clk_100mhz = ~clk_100mhz;
    end

    initial begin
        $dumpfile("raisin64.vcd");
        $dumpvars;
    end

    initial
    begin
        rst_n = 0;
        SW = 16'h1234;

        #15 rst_n = 1;

        #400 SW = 16'h5454;
        #400 SW = 16'h8263;

        #100000 $finish;
    end

endmodule
