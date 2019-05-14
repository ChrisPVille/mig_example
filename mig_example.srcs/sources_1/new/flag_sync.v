module flag_sync(
    input a_rst_n,
    input a_clk,
    input a_flag,
    input b_rst_n,
    input b_clk,
    output b_flag
    );

    reg flag;
    always @(posedge a_clk or negedge a_rst_n) begin
        if(~a_rst_n) flag <= 0;
	else flag <= flag ^ a_flag;
    end

    (* ASYNC_REG = "TRUE" *) reg[2:0] flag_sync;
    always @(posedge b_clk or negedge b_rst_n) begin
        if(~b_rst_n) flag_sync <= 3'h0;
	else flag_sync <= {flag_sync[1:0], flag};
    end

    assign b_flag = flag_sync[1] ^ flag_sync[2];

endmodule
