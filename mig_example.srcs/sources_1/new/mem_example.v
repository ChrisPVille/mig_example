//We have configured the MIG in 2:1 mode to simplify the clocking
//requirements. Note that the underlying transaction size is still 128-bits.
//In 2:1 mode, we are required to read and write our data across 2 cycles
//in 64-bit chunks. This can be done internal to the module so we still present
//128-bit ports to the rest of the design.
//
//As the 128-bit mode is a bit of overkill for this example, the upper 64-bits are
//always masked off and aren't available external to the module.
//
//A happy side-effect of the 2:1 mode (vs 4:1 mode) is that ui_clk runs at
//double the speed, decreasing the delay of the clock domain crossing from the
//CPU into the ui_*/app_* memory controller domain.

`include "io_def.vh"

module mem_example(
    input clk_mem,
    input rst_n,

    inout[15:0] ddr2_dq,
    inout[1:0] ddr2_dqs_n,
    inout[1:0] ddr2_dqs_p,
    output[12:0] ddr2_addr,
    output[2:0] ddr2_ba,
    output ddr2_ras_n,
    output ddr2_cas_n,
    output ddr2_we_n,
    output[0:0] ddr2_ck_p,
    output[0:0] ddr2_ck_n,
    output[0:0] ddr2_cke,
    output[0:0] ddr2_cs_n,
    output[1:0] ddr2_dm,
    output[0:0] ddr2_odt,

    input cpu_clk,
    input[27:0] addr,
    input[1:0] width,
    input[63:0] data_in,
    output reg[63:0] data_out,
    input rstrobe,
    input wstrobe,
    output transaction_complete,
    output ready
    );

    wire ui_clk, ui_clk_sync_rst;

    reg[2:0] mem_cmd;
    reg mem_en;
    wire mem_rdy;

    wire mem_rd_data_end, mem_rd_data_valid;
    wire[63:0] mem_rd_data;

    reg[63:0] mem_wdf_data;
    reg mem_wdf_end, mem_wdf_wren;
    reg[7:0] mem_wdf_mask;
    wire mem_wdf_rdy;

    mig mig1 (
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
        .init_calib_complete(),

        .ddr2_cs_n(ddr2_cs_n),
        .ddr2_dm(ddr2_dm),
        .ddr2_odt(ddr2_odt),

        .app_addr(addr[27:1]),
        .app_cmd(mem_cmd),
        .app_en(mem_en),
        .app_wdf_data(mem_wdf_data),
        .app_wdf_end(mem_wdf_end),
        .app_wdf_wren(mem_wdf_wren),
        .app_rd_data(mem_rd_data),
        .app_rd_data_end(mem_rd_data_end),
        .app_rd_data_valid(mem_rd_data_valid),
        .app_rdy(mem_rdy),
        .app_wdf_rdy(mem_wdf_rdy),
        .app_sr_req(1'b0),
        .app_ref_req(1'b0),
        .app_zq_req(1'b0),
        .app_sr_active(),
        .app_ref_ack(),
        .app_zq_ack(),
        .ui_clk(ui_clk),
        .ui_clk_sync_rst(ui_clk_sync_rst),

        .app_wdf_mask(mem_wdf_mask),

        .sys_clk_i(clk_mem),
        .sys_rst(rst_n)
        );

    //Addresses and data remain stable from the initial strobe till the end of
    //the transaction. It is only necessary to synchronize the strobes.
    wire rstrobe_sync, wstrobe_sync;

    flag_sync rs_sync(
        .a_rst_n(rst_n),
        .a_clk(cpu_clk),
        .a_flag(rstrobe),
        .b_rst_n(~ui_clk_sync_rst),
        .b_clk(ui_clk),
        .b_flag(rstrobe_sync)
        );

    flag_sync ws_sync(
        .a_rst_n(rst_n),
        .a_clk(cpu_clk),
        .a_flag(wstrobe),
        .b_rst_n(~ui_clk_sync_rst),
        .b_clk(ui_clk),
        .b_flag(wstrobe_sync)
        );

    reg complete;

    flag_sync complete_sync(
        .a_rst_n(~ui_clk_sync_rst),
        .a_clk(ui_clk),
        .a_flag(complete),
        .b_rst_n(rst_n),
        .b_clk(cpu_clk),
        .b_flag(transaction_complete)
        );

    ff_sync ready_sync(
        .clk(cpu_clk),
        .rst_p(~rst_n),
        .in_async(~ui_clk_sync_rst),
        .out(ready)
        );

    reg[2:0] state;

    localparam STATE_IDLE = 3'h0;
    localparam STATE_PREREAD = 3'h1;
    localparam STATE_READ = 3'h2;
    localparam STATE_WRITE = 3'h4;
    localparam STATE_WRITEDATA_H = 3'h5;
    localparam STATE_WRITEDATA_L = 3'h6;

    localparam CMD_READ = 3'h1;
    localparam CMD_WRITE = 3'h0;

    //mem_rd_data becomes ready the same cycle as mem_rdy is asserted and
    //otherwise has no relationship with mem_rdy. mem_rd_data_valid is the
    //only authoritative trigger for registering read bytes.
    always @(posedge ui_clk) begin
        if(ui_clk_sync_rst) begin
            data_out <= 64'h0;
        end else begin
            if (state == STATE_READ && mem_rd_data_valid || //Data is available normally
                state == STATE_PREREAD && mem_rdy && mem_rd_data_valid) begin //Data happens to be available immediately
                if(~addr[0]) begin
                    if(~mem_rd_data_end) case(width)
                        `RAM_WIDTH64: data_out[63:0] <= {mem_rd_data[7:0],mem_rd_data[15:8],
                                                   mem_rd_data[23:16],mem_rd_data[31:24],
                                                   mem_rd_data[39:32],mem_rd_data[47:40],
                                                   mem_rd_data[55:48],mem_rd_data[63:56]};
                        `RAM_WIDTH32: data_out[63:0] <= {mem_rd_data[7:0],mem_rd_data[15:8],
                                                   mem_rd_data[23:16],mem_rd_data[31:24],32'h0};
                        `RAM_WIDTH16: data_out[63:0] <= {mem_rd_data[7:0],mem_rd_data[15:8],48'h0};
                        `RAM_WIDTH8: data_out[63:0] <= {mem_rd_data[7:0],56'h0};
                    endcase
                end else begin
                    if(mem_rd_data_end) begin
                        if(width == `RAM_WIDTH64) data_out[7:0] <= mem_rd_data[7:0];
                    end else case(width)
                        `RAM_WIDTH64: data_out[63:8] <= {mem_rd_data[15:8],mem_rd_data[23:16],
                                                         mem_rd_data[31:24],mem_rd_data[39:32],
                                                         mem_rd_data[47:40],mem_rd_data[55:48],
                                                         mem_rd_data[63:56]};
                        `RAM_WIDTH32: data_out[63:0] <= {mem_rd_data[15:8],mem_rd_data[23:16],
                                                         mem_rd_data[31:24],mem_rd_data[39:32],32'h0};
                        `RAM_WIDTH16: data_out[63:0] <= {mem_rd_data[15:8],mem_rd_data[23:16],48'h0};
                        `RAM_WIDTH8: data_out[63:0]  <= {mem_rd_data[15:8],56'h0};
                    endcase
                end
            end
        end
    end

    //The Command and Write Data queues are independent
    always @(posedge ui_clk) begin
        if(ui_clk_sync_rst) begin
            state <= STATE_IDLE;
            complete <= 0;
            mem_cmd <= CMD_WRITE;
            mem_wdf_mask <= 8'h00;
            mem_wdf_data <= 64'h0;
            mem_wdf_wren <= 0;
            mem_wdf_end <= 0;
            mem_en <= 0;
        end else begin
            complete <= 0;

            case(state)

            STATE_IDLE: begin
                mem_wdf_wren <= 0;
                if(wstrobe_sync) begin
                    mem_en <= 1;
                    mem_cmd <= CMD_WRITE;
                    mem_wdf_end <= 0;
                    state <= STATE_WRITE;
                end
                else if(rstrobe_sync) begin
                    mem_en <= 1;
                    mem_cmd <= CMD_READ;
                    state <= STATE_PREREAD;
                end
            end

            STATE_WRITEDATA_H: begin
                if(mem_wdf_rdy) begin //Wait for Write Data queue to have space
                    if(~addr[0]) case(width)
                        `RAM_WIDTH64: begin
                            mem_wdf_mask <= 8'h00;
                            mem_wdf_data <= {data_in[7:0],data_in[15:8],data_in[23:16],data_in[31:24],
                                             data_in[39:32],data_in[47:40],data_in[55:48],data_in[63:56]};
                        end
                        `RAM_WIDTH32: begin
                            mem_wdf_mask <= 8'hF0;
                            mem_wdf_data <= {32'h0,data_in[7:0],data_in[15:8],data_in[23:16],data_in[31:24]};
                        end
                        `RAM_WIDTH16: begin
                            mem_wdf_mask <= 8'hFC;
                            mem_wdf_data <= {48'h0,data_in[7:0],data_in[15:8]};
                        end
                        `RAM_WIDTH8: begin
                            mem_wdf_mask <= 8'hFE;
                            mem_wdf_data <= {56'h0,data_in[7:0]};
                        end
                        endcase
                    else case(width)
                        `RAM_WIDTH64: begin
                            mem_wdf_mask <= 8'h01;
                            mem_wdf_data <= {data_in[15:8],data_in[23:16],data_in[31:24],
                                             data_in[39:32],data_in[47:40],data_in[55:48],data_in[63:56],8'h0};
                        end
                        `RAM_WIDTH32: begin
                            mem_wdf_mask <= 8'hE1;
                            mem_wdf_data <= {24'h0,data_in[7:0],data_in[15:8],data_in[23:16],data_in[31:24],8'h0};
                        end
                        `RAM_WIDTH16: begin
                            mem_wdf_mask <= 8'hF9;
                            mem_wdf_data <= {40'h0,data_in[7:0],data_in[15:8],8'h0};
                        end
                        `RAM_WIDTH8: begin
                            mem_wdf_mask <= 8'hFD;
                            mem_wdf_data <= {48'h0,data_in[7:0],8'h0};
                        end
                        endcase

                    mem_wdf_wren <= 1;
                    state <= STATE_WRITEDATA_L;
                end
            end

            STATE_WRITEDATA_L: begin
                if(mem_wdf_rdy) begin //Wait for Write Data queue to have space
                    if(~addr[0]) begin
                        mem_wdf_mask <= 8'hFF;
                        mem_wdf_data <= 64'h0;
                    end else begin
                        mem_wdf_mask <= 8'hFE;
                        mem_wdf_data <= {56'h0,data_in[7:0]};
                    end
                    mem_wdf_wren <= 1;
                    mem_wdf_end <= 1;
                    complete <= 1;
                    state <= STATE_IDLE;
                end
            end

            STATE_PREREAD: begin
                if(mem_rdy) begin //Wait for command queue to accept command
                    mem_en <= 0;
                    state <= STATE_READ;
                    if(mem_rd_data_valid & mem_rd_data_end) begin //If data happens to be available now
                        state <= STATE_IDLE;
                        complete <= 1;
                    end
                end
            end

            STATE_READ: begin
                if(mem_rd_data_valid & mem_rd_data_end) begin
                    state <= STATE_IDLE;
                    complete <= 1;
                end
            end

            STATE_WRITE: begin
                if(mem_rdy) begin //Wait for command queue to accept command
                    mem_en <= 0;
                    state <= STATE_WRITEDATA_H;
                end
            end
            endcase
        end
    end
endmodule
