// Reference implementation: zeroriscy_alu
// Matches the zero-riscy ALU interface from PULPino.
// This is a self-contained version (no package imports) suitable for VerilogEval.

module zeroriscy_alu (
  input  logic [5:0]  operator_i,
  input  logic [31:0] operand_a_i,
  input  logic [31:0] operand_b_i,

  output logic [31:0] adder_result_o,
  output logic [31:0] result_o
);

  // Operation encoding (matches zeroriscy_defines)
  localparam ALU_ADD  = 6'b011000;
  localparam ALU_SUB  = 6'b011001;
  localparam ALU_AND  = 6'b010101;
  localparam ALU_OR   = 6'b010100;
  localparam ALU_XOR  = 6'b010011;
  localparam ALU_SLL  = 6'b100111;
  localparam ALU_SRL  = 6'b100101;
  localparam ALU_SRA  = 6'b100100;
  localparam ALU_SLT  = 6'b000010;
  localparam ALU_SLTU = 6'b000011;
  localparam ALU_LUI  = 6'b001111;

  logic [31:0] operand_b_neg;
  logic [31:0] adder_in_a, adder_in_b;
  logic        adder_sub;

  // Adder/subtractor
  assign adder_sub    = (operator_i == ALU_SUB) || (operator_i == ALU_SLT) || (operator_i == ALU_SLTU);
  assign operand_b_neg = ~operand_b_i + 32'd1;
  assign adder_in_a   = operand_a_i;
  assign adder_in_b   = adder_sub ? operand_b_neg : operand_b_i;
  assign adder_result_o = adder_in_a + adder_in_b;

  // Shift amount
  logic [4:0] shift_amt;
  assign shift_amt = operand_b_i[4:0];

  // Result mux
  always_comb begin
    result_o = 32'd0;
    case (operator_i)
      ALU_ADD:  result_o = adder_result_o;
      ALU_SUB:  result_o = adder_result_o;
      ALU_AND:  result_o = operand_a_i & operand_b_i;
      ALU_OR:   result_o = operand_a_i | operand_b_i;
      ALU_XOR:  result_o = operand_a_i ^ operand_b_i;
      ALU_SLL:  result_o = operand_a_i << shift_amt;
      ALU_SRL:  result_o = operand_a_i >> shift_amt;
      ALU_SRA:  result_o = $signed(operand_a_i) >>> shift_amt;
      ALU_SLT:  result_o = ($signed(operand_a_i) < $signed(operand_b_i)) ? 32'd1 : 32'd0;
      ALU_SLTU: result_o = (operand_a_i < operand_b_i) ? 32'd1 : 32'd0;
      ALU_LUI:  result_o = operand_b_i;
      default:  result_o = 32'd0;
    endcase
  end

endmodule
