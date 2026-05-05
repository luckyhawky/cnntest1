//==============================================================================
// FILE: auc_multiply_8bit.v
// DESCRIPTION: 8x8 Multiplier
// 
//==============================================================================
module auc_multiply_8bit(
    input  [7:0] a,
    input  [7:0] b,
    output [15:0] res 
);

   
    wire [3:0] a_h = a[7:4];
    wire [3:0] a_l = a[3:0];
    wire [3:0] b_h = b[7:4];
    wire [3:0] b_l = b[3:0];

    
    wire [7:0] p_hh; // Weight 256
    wire [7:0] p_hl; // Weight 16
    wire [7:0] p_lh; // Weight 16
    wire [7:0] p_ll; // Weight 1

    auc_lut_4x4 u_hh (.a(a_h), .b(b_h), .p(p_hh));
    auc_lut_4x4 u_hl (.a(a_h), .b(b_l), .p(p_hl));
    auc_lut_4x4 u_lh (.a(a_l), .b(b_h), .p(p_lh));
    auc_lut_4x4 u_ll (.a(a_l), .b(b_l), .p(p_ll));

    
    wire [8:0] mid_sum = p_hl + p_lh; 
    
   
    assign res = {p_hh, 8'b0} + {mid_sum, 4'b0} + p_ll;

endmodule

//==============================================================================
// SUB-MODULE: 4-bit LUT
//==============================================================================
module auc_lut_4x4(
    input  [3:0] a,
    input  [3:0] b,
    output reg [7:0] p
);
   
    always @(*) begin
        p = a * b; 
    end
endmodule