module ff_sync #(parameter WIDTH=1)(
    input clk,
    input rst_p,
    input[WIDTH-1:0] in_async,
    output reg[WIDTH-1:0] out);
    
    (* ASYNC_REG = "TRUE" *) reg[WIDTH-1:0] sync_reg;
    always @(posedge clk, posedge rst_p) begin
        if(rst_p) begin
            sync_reg <= 0;
            out <= 0;
        end else begin
            {out, sync_reg} <= {sync_reg, in_async};
        end
    end
    
endmodule
