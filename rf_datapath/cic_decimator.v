`timescale 1ns/1ps

module cic_decimator #(
    parameter DIN_WIDTH  = 12,
    parameter DOUT_WIDTH = 12
    )
    (
    input        clk                           ,
    input        rst_n                         ,
    input  [1:0] i_dec_ratio                   ,
    input        signed [DIN_WIDTH-1:0]  i_data,
    input        i_data_vld                    ,
    output       signed [DOUT_WIDTH-1:0] o_data,
    output       o_data_vld
    );

  localparam ACC_WIDTH = DIN_WIDTH + 6;

    reg signed [ACC_WIDTH-1:0] integ1, integ2, integ3;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        integ1 <= {ACC_WIDTH{1'b0}};
        integ2 <= {ACC_WIDTH{1'b0}};
        integ3 <= {ACC_WIDTH{1'b0}};
    end else if (i_data_vld) begin
        integ1 <= integ1 + $signed({{(ACC_WIDTH-DIN_WIDTH){i_data[DIN_WIDTH-1]}}, i_data});
        integ2 <= integ2 + integ1;
        integ3 <= integ3 + integ2;
    end
end

    reg            [2:0] dec_cnt          ;
    reg                  dec_tick         ;
    reg  signed [ACC_WIDTH-1:0] integ3_dec;

    wire           [2:0] dec_max          ;
assign dec_max = (i_dec_ratio == 2'd1) ? 3'd1 :
                  (i_dec_ratio == 2'd2) ? 3'd3 :
                  3'd0;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dec_cnt    <= 3'd0;
        dec_tick   <= 1'b0;
        integ3_dec <= {ACC_WIDTH{1'b0}};
    end else if (i_data_vld) begin
        if (dec_cnt >= dec_max) begin
            dec_cnt    <= 3'd0;
            dec_tick   <= 1'b1;
            integ3_dec <= integ3;
        end else begin
            dec_cnt    <= dec_cnt + 1'b1;
            dec_tick   <= 1'b0;
        end
    end else begin
        dec_tick   <= 1'b0;
    end
end

reg signed [ACC_WIDTH-1:0] comb1_d, comb1_out            ;
reg signed [ACC_WIDTH-1:0] comb2_d, comb2_out            ;
reg signed [ACC_WIDTH-1:0] comb3_d, comb3_out            ;
reg                 comb_vld_p1, comb_vld_p2, comb_vld_p3;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        comb1_d     <= {ACC_WIDTH{1'b0}};
        comb1_out   <= {ACC_WIDTH{1'b0}};
        comb_vld_p1 <= 1'b0;
    end else begin
        comb_vld_p1 <= dec_tick;
        if (dec_tick) begin
            comb1_out   <= integ3_dec - comb1_d;
            comb1_d     <= integ3_dec;
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        comb2_d     <= {ACC_WIDTH{1'b0}};
        comb2_out   <= {ACC_WIDTH{1'b0}};
        comb_vld_p2 <= 1'b0;
    end else begin
        comb_vld_p2 <= comb_vld_p1;
        if (comb_vld_p1) begin
            comb2_out   <= comb1_out - comb2_d;
            comb2_d     <= comb1_out;
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        comb3_d     <= {ACC_WIDTH{1'b0}};
        comb3_out   <= {ACC_WIDTH{1'b0}};
        comb_vld_p3 <= 1'b0;
    end else begin
        comb_vld_p3 <= comb_vld_p2;
        if (comb_vld_p2) begin
            comb3_out   <= comb2_out - comb3_d;
            comb3_d     <= comb2_out;
        end
    end
end

reg                   out_vld_r        ;
reg  signed [DOUT_WIDTH-1:0] out_data_r;

wire            [3:0] shift_bits       ;
assign shift_bits = (i_dec_ratio == 2'd1) ? 4'd3 :
                     (i_dec_ratio == 2'd2) ? 4'd6 :
                     4'd0;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        out_vld_r  <= 1'b0;
        out_data_r <= {DOUT_WIDTH{1'b0}};
    end else begin
        out_vld_r  <= comb_vld_p3;
        if (comb_vld_p3)
            out_data_r <= comb3_out >>> shift_bits;
    end
end

assign o_data     = (i_dec_ratio == 2'd0) ? i_data : out_data_r   ;
assign o_data_vld = (i_dec_ratio == 2'd0) ? i_data_vld : out_vld_r;

endmodule
