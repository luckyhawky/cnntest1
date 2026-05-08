
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



endmodule
