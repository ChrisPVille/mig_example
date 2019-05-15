module mig_example_top(
    input CLK100MHZ,
    input CPU_RESETN,

    //RAM Interface
    inout[15:0] ddr2_dq,
    inout[1:0] ddr2_dqs_n,
    inout[1:0] ddr2_dqs_p,
    output[12:0] ddr2_addr,
    output[2:0] ddr2_ba,
    output ddr2_ras_n,
    output ddr2_cas_n,
    output ddr2_we_n,
    output ddr2_ck_p,
    output ddr2_ck_n,
    output ddr2_cke,
    output ddr2_cs_n,
    output[1:0] ddr2_dm,
    output ddr2_odt
    );

    //////////  Clock Generation  //////////
    wire clk_cpu, clk_in;
    wire dig_pll_locked;

    IBUFG clk_in_buf (.I(CLK100MHZ), .O(clk_in));

    clk_synth cpu_pll(
        .locked(dig_pll_locked),
        .clk_in(clk_in),
        .clk_cpu(clk_cpu)
        );

    //////////  Reset Sync/Stretch  //////////
    reg[31:0] rst_stretch = 32'hFFFFFFFF;
    wire reset_req_n, rst_n;

    assign reset_req_n = CPU_RESETN & dig_pll_locked;

    always @(posedge clk_cpu) rst_stretch = {reset_req_n,rst_stretch[31:1]};
    assign rst_n = reset_req_n & &rst_stretch;

    //////////  DUT  //////////
    wire[27:0] mem_addr;
    wire[1:0] mem_transaction_width;
    wire[63:0] mem_d_to_ram;
    wire[63:0] mem_d_from_ram;
    wire mem_wstrobe, mem_rstrobe;
    wire mem_transaction_complete;
    
    mem_example mem_ex(
        .clk_100mhz(clk_in),
        .rst_n(rst_n),

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

        .cpu_clk(clk_cpu),
        .addr(mem_addr),
        .width(mem_transaction_width),
        .data_in(mem_d_to_ram),
        .data_out(mem_d_from_ram),
        .rstrobe(mem_rstrobe),
        .wstrobe(mem_wstrobe),
        .transaction_complete(mem_transaction_complete),
        .ready(mem_transaction_complete)
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
    always @(posedge clk_cpu or negedge rst_n) begin
        if(~rst_n) led_reg <= 16'h0;
        else if(led_en & mem_from_cpu_write) led_reg <= mem_from_cpu;
    end

    assign LED[15:0] = led_reg;

    //SW uses a small synchronizer
    reg[15:0] sw_pre0, sw_pre1;
    always @(posedge clk_cpu or negedge rst_n) begin
        if(~rst_n) begin
            sw_pre0 <= 16'h0;
            sw_pre1 <= 16'h0;
        end else begin
            sw_pre0 <= sw_pre1;
            sw_pre1 <= SW;
        end
    end

    //VGA System
    wire[15:0] vga_dout;
    //Again, for now we take the lower bits from a fully-aligned access. This
    //will be trivial to change in the future.
    vgaCharGen #(
        .SINGLE_CYCLE_DESIGN(0) //Allow the registering of cpu_data outputs
        ) vga_cg(
        .pixel_clk(clk_vga),
        .rst_p(~rst_n),
        .pixel_clkEn(1'b1),
        .cpu_clk(clk_cpu),
        .cpu_addr(mem_addr[18:3]),
        .cpu_oe(vga_en),
        .cpu_we(vga_en & mem_from_cpu_write),
        .cpu_dataIn(mem_from_cpu[15:0]),
        .cpu_dataOut(vga_dout),
        .VGA_R(VGA_R),
        .VGA_G(VGA_G),
        .VGA_B(VGA_B),
        .VGA_HS(VGA_HS),
        .VGA_VS(VGA_VS)
        );

    //Data selection
    assign mem_to_cpu_ready = mem_addr_valid;
    assign mem_to_cpu = sw_en ? sw_pre0 :
                        vga_en ? vga_dout :
                        64'h0;

endmodule
