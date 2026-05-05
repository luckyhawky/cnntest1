
`include "multiplyer.v"

module cnntest #(
    parameter IMG_WIDTH_MAX = 1920, 
    parameter I2C_ADDR = 7'h5A      // 7-bit I2C address
)(
    // --- Global Signals ---
    input  wire        clk,
    input  wire        rst_n,

    // --- Video Input Stream ---
    input  wire        i_valid,
    input  wire [7:0]  i_pixel,
    input  wire        i_vsync,

    // --- Feature Map Output Stream ---
    output reg         o_valid,
    output reg  [7:0]  o_feature,
    output reg         o_vsync,

    // --- I2C Configuration Interface ---
    input  wire        i2c_scl,
    inout  wire        i2c_sda
);

//==============================================================================
//
//==============================================================================
reg [7:0]  cfg_ctrl;
reg [15:0] cfg_img_width;
reg [7:0]  cfg_act_mode;
reg [7:0]  cfg_act_param;
reg [7:0]  cfg_pool_mode; 

reg [71:0] cfg_kernel_a;
reg [71:0] cfg_kernel_b;
reg        cfg_kernel_select; 

wire ip_en       = cfg_ctrl[0];
wire soft_reset  = cfg_ctrl[1];
wire auto_swap   = cfg_ctrl[4];

assign i2c_sda = 1'bz; //

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cfg_ctrl <= 8'h01; 
        cfg_img_width <= IMG_WIDTH_MAX; 
        cfg_act_mode <= 2'h0; 
        cfg_act_param <= 8'h0; 
        cfg_pool_mode <= 2'h0; 
        cfg_kernel_a <= 72'h0000010000FEFFFF01; 
        cfg_kernel_b <= 72'h0;
        cfg_kernel_select <= 1'b0;
    end else begin
        if (auto_swap && i_vsync) begin
             cfg_kernel_select <= ~cfg_kernel_select;
        end
    end
end

//==============================================================================
//
//==============================================================================
// 
(* ramstyle = "M9K" *) reg [7:0] line_buffer1 [0:IMG_WIDTH_MAX-1];
(* ramstyle = "M9K" *) reg [7:0] line_buffer2 [0:IMG_WIDTH_MAX-1];

reg [15:0] x_coord;
reg [15:0] y_coord;
reg [7:0]  win_reg [0:8]; 

// 
reg [15:0] x_coord_d1;
reg        i_valid_d1;

always @(posedge clk) begin
    if (!rst_n || soft_reset) begin
        x_coord <= 0;
        y_coord <= 0;
        x_coord_d1 <= 0;
        i_valid_d1 <= 0;
    end else begin
        // 
        x_coord_d1 <= x_coord;
        i_valid_d1 <= i_valid && ip_en;

        if (i_valid) begin
            if (x_coord == cfg_img_width - 1) begin
                x_coord <= 0;
                y_coord <= y_coord + 1;
            end else begin
                x_coord <= x_coord + 1;
            end
        end
        if (i_vsync) begin
            x_coord <= 0;
            y_coord <= 0;
        end
    end
end

// 
always @(posedge clk) begin
    if (i_valid && ip_en) begin
        win_reg[2] <= i_pixel;
        win_reg[1] <= win_reg[2];
        win_reg[0] <= win_reg[1];
        
        //
        win_reg[5] <= line_buffer1[x_coord];
        win_reg[4] <= win_reg[5];
        win_reg[3] <= win_reg[4];
        
        //
        win_reg[8] <= line_buffer2[x_coord];
        win_reg[7] <= win_reg[8];
        win_reg[6] <= win_reg[7];
        
        // 
        line_buffer1[x_coord] <= i_pixel;
    end
end

// 
// 
always @(posedge clk) begin
    if (i_valid_d1) begin
        // 
        line_buffer2[x_coord_d1] <= win_reg[5];
    end
end

reg s1_valid; 
always @(posedge clk) begin
    s1_valid <= (y_coord >= 2) && (x_coord >= 2) && i_valid && ip_en;
end


//==============================================================================
// 
//==============================================================================
wire [71:0] active_kernel = cfg_kernel_select ? cfg_kernel_b : cfg_kernel_a;
wire [7:0]  kernel_w [0:8];
wire [15:0] mul_results [0:8];

reg  [19:0] s2_conv_sum; 
reg         s2_valid;

genvar j;
generate
for (j=0; j<9; j=j+1) begin: kernel_unpacker
    assign kernel_w[j] = active_kernel[8*(j+1)-1 -: 8];
end
endgenerate

generate
    genvar i;
    for (i = 0; i < 9; i = i + 1) begin : mul_gen
        wire [7:0] abs_weight = (kernel_w[i][7]) ? -kernel_w[i] : kernel_w[i];
        wire [15:0] abs_prod;

        auc_multiply_8bit auc_inst (
            .a(win_reg[i]),      
            .b(abs_weight),      
            .res(abs_prod)       
        );
        assign mul_results[i] = (kernel_w[i][7]) ? -abs_prod : abs_prod;
    end
endgenerate

always @(posedge clk) begin
    s2_valid <= s1_valid;
    if (s1_valid) begin
        s2_conv_sum <= mul_results[0] + mul_results[1] + mul_results[2] +
                       mul_results[3] + mul_results[4] + mul_results[5] +
                       mul_results[6] + mul_results[7] + mul_results[8];
    end
end

//==============================================================================
// 
//==============================================================================
reg [19:0] s3_act_out;
reg        s3_valid;

reg s2_vsync, s3_vsync;
wire s1_is_vsync = (y_coord == (cfg_img_width - 1)) && (x_coord == (cfg_img_width - 1));

always @(posedge clk) begin
    s2_vsync <= s1_is_vsync;
    s3_vsync <= s2_vsync;
end

wire [19:0] sum = s2_conv_sum;
wire [7:0] bias_or_limit = cfg_act_param;
wire [3:0] shift = cfg_act_param[3:0]; 

always @(posedge clk) begin
    s3_valid <= s2_valid;
    if(s2_valid) begin
        case (cfg_act_mode[1:0])
            2'b00: s3_act_out <= (sum > bias_or_limit) ? (sum - bias_or_limit) : 0; 
            2'b01: s3_act_out <= (sum[19] == 0) ? sum : (sum >>> shift);            
            2'b10: s3_act_out <= (sum < 0) ? 0 : (sum > bias_or_limit ? bias_or_limit : sum); 
            default: s3_act_out <= sum >>> shift; 
        endcase
    end
end

//==============================================================================
//
//==============================================================================
reg [7:0] s3_act_8bit;

always @(*) begin
    if (s3_act_out[19]) s3_act_8bit = 8'h00; 
    else if (s3_act_out > 255) s3_act_8bit = 8'hFF;
    else s3_act_8bit = s3_act_out[7:0];
end

always @(posedge clk) begin
    o_valid <= 0;
    o_vsync <= s3_vsync; 

    if (s3_valid && ip_en) begin
        o_feature <= s3_act_8bit;
        o_valid   <= 1;
    end
end

endmodule