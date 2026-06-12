// Self-checking testbench for zeroriscy_alu
// Compatible with iverilog v12. No $urandom — uses fixed vectors.
// Exits with $finish. Prints PASS or FAIL per test, summary at end.

`timescale 1ns/1ps

module tb_zeroriscy_alu;

  // DUT ports
  logic [5:0]  operator_i;
  logic [31:0] operand_a_i;
  logic [31:0] operand_b_i;
  logic [31:0] adder_result_o;
  logic [31:0] result_o;

  // Instantiate DUT
  zeroriscy_alu dut (
    .operator_i    (operator_i),
    .operand_a_i   (operand_a_i),
    .operand_b_i   (operand_b_i),
    .adder_result_o(adder_result_o),
    .result_o      (result_o)
  );

  // Operation encodings
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

  // Test bookkeeping
  integer pass_count;
  integer fail_count;

  task apply_and_check;
    input [5:0]  op;
    input [31:0] a;
    input [31:0] b;
    input [31:0] expected_result;
    input [31:0] expected_adder;
    input [63:0] test_id;
    begin
      operator_i  = op;
      operand_a_i = a;
      operand_b_i = b;
      #5; // wait for combinational settle
      if (result_o !== expected_result) begin
        $display("FAIL test %0d: op=%06b a=%08h b=%08h | got result=%08h expected=%08h",
                 test_id, op, a, b, result_o, expected_result);
        fail_count = fail_count + 1;
      end else if (expected_adder !== 32'hXXXXXXXX &&
                   adder_result_o !== expected_adder) begin
        $display("FAIL test %0d: op=%06b a=%08h b=%08h | got adder=%08h expected=%08h",
                 test_id, op, a, b, adder_result_o, expected_adder);
        fail_count = fail_count + 1;
      end else begin
        $display("PASS test %0d: op=%06b a=%08h b=%08h => %08h", test_id, op, a, b, result_o);
        pass_count = pass_count + 1;
      end
    end
  endtask

  integer i;

  initial begin
    pass_count = 0;
    fail_count = 0;
    operator_i  = 0;
    operand_a_i = 0;
    operand_b_i = 0;
    #10;

    // ── ADD ──────────────────────────────────────────────────────────
    apply_and_check(ALU_ADD, 32'd10,         32'd20,         32'd30,          32'd30,          1);
    apply_and_check(ALU_ADD, 32'hFFFFFFFF,   32'd1,          32'd0,           32'd0,           2); // overflow wraps
    apply_and_check(ALU_ADD, 32'd0,          32'd0,          32'd0,           32'd0,           3);
    apply_and_check(ALU_ADD, 32'h7FFFFFFF,   32'd1,          32'h80000000,    32'h80000000,    4); // max positive + 1

    // ── SUB ──────────────────────────────────────────────────────────
    apply_and_check(ALU_SUB, 32'd30,         32'd10,         32'd20,          32'd20,          5);
    apply_and_check(ALU_SUB, 32'd0,          32'd1,          32'hFFFFFFFF,    32'hFFFFFFFF,    6); // underflow wraps
    apply_and_check(ALU_SUB, 32'd100,        32'd100,        32'd0,           32'd0,           7);

    // ── AND ──────────────────────────────────────────────────────────
    apply_and_check(ALU_AND, 32'hFFFFFFFF,   32'h0F0F0F0F,  32'h0F0F0F0F,   32'hXXXXXXXX,   8);
    apply_and_check(ALU_AND, 32'hAAAAAAAA,   32'h55555555,  32'h00000000,   32'hXXXXXXXX,   9);
    apply_and_check(ALU_AND, 32'hDEADBEEF,   32'hFFFFFFFF,  32'hDEADBEEF,   32'hXXXXXXXX,  10);

    // ── OR ───────────────────────────────────────────────────────────
    apply_and_check(ALU_OR,  32'hAAAAAAAA,   32'h55555555,  32'hFFFFFFFF,   32'hXXXXXXXX,  11);
    apply_and_check(ALU_OR,  32'h00000000,   32'h00000000,  32'h00000000,   32'hXXXXXXXX,  12);
    apply_and_check(ALU_OR,  32'hDEAD0000,   32'h0000BEEF,  32'hDEADBEEF,   32'hXXXXXXXX,  13);

    // ── XOR ──────────────────────────────────────────────────────────
    apply_and_check(ALU_XOR, 32'hFFFFFFFF,   32'hFFFFFFFF,  32'h00000000,   32'hXXXXXXXX,  14);
    apply_and_check(ALU_XOR, 32'hAAAAAAAA,   32'h55555555,  32'hFFFFFFFF,   32'hXXXXXXXX,  15);
    apply_and_check(ALU_XOR, 32'hDEADBEEF,   32'h00000000,  32'hDEADBEEF,   32'hXXXXXXXX,  16);

    // ── SLL ──────────────────────────────────────────────────────────
    apply_and_check(ALU_SLL, 32'h00000001,   32'd4,          32'h00000010,   32'hXXXXXXXX,  17);
    apply_and_check(ALU_SLL, 32'hFFFFFFFF,   32'd1,          32'hFFFFFFFE,   32'hXXXXXXXX,  18);
    apply_and_check(ALU_SLL, 32'h00000001,   32'd31,         32'h80000000,   32'hXXXXXXXX,  19);
    apply_and_check(ALU_SLL, 32'hDEADBEEF,   32'd0,          32'hDEADBEEF,   32'hXXXXXXXX,  20); // shift by 0

    // ── SRL ──────────────────────────────────────────────────────────
    apply_and_check(ALU_SRL, 32'h80000000,   32'd1,          32'h40000000,   32'hXXXXXXXX,  21); // no sign extension
    apply_and_check(ALU_SRL, 32'hFFFFFFFF,   32'd4,          32'h0FFFFFFF,   32'hXXXXXXXX,  22);
    apply_and_check(ALU_SRL, 32'hFFFFFFFF,   32'd31,         32'h00000001,   32'hXXXXXXXX,  23);

    // ── SRA ──────────────────────────────────────────────────────────
    apply_and_check(ALU_SRA, 32'h80000000,   32'd1,          32'hC0000000,   32'hXXXXXXXX,  24); // sign extended
    apply_and_check(ALU_SRA, 32'hFFFFFFFF,   32'd4,          32'hFFFFFFFF,   32'hXXXXXXXX,  25); // all ones stays all ones
    apply_and_check(ALU_SRA, 32'h7FFFFFFF,   32'd1,          32'h3FFFFFFF,   32'hXXXXXXXX,  26); // positive stays positive

    // ── SLT (signed) ─────────────────────────────────────────────────
    apply_and_check(ALU_SLT, 32'hFFFFFFFF,   32'd1,          32'd1,          32'hXXXXXXXX,  27); // -1 < 1 → 1
    apply_and_check(ALU_SLT, 32'd1,          32'hFFFFFFFF,   32'd0,          32'hXXXXXXXX,  28); // 1 < -1 → 0
    apply_and_check(ALU_SLT, 32'd5,          32'd5,          32'd0,          32'hXXXXXXXX,  29); // equal → 0
    apply_and_check(ALU_SLT, 32'h80000000,   32'h7FFFFFFF,   32'd1,          32'hXXXXXXXX,  30); // INT_MIN < INT_MAX → 1

    // ── SLTU (unsigned) ──────────────────────────────────────────────
    apply_and_check(ALU_SLTU, 32'd1,         32'hFFFFFFFF,   32'd1,          32'hXXXXXXXX,  31); // 1 < 0xFFFFFFFF → 1
    apply_and_check(ALU_SLTU, 32'hFFFFFFFF,  32'd1,          32'd0,          32'hXXXXXXXX,  32); // 0xFFFFFFFF < 1 → 0
    apply_and_check(ALU_SLTU, 32'd0,         32'd0,          32'd0,          32'hXXXXXXXX,  33); // equal → 0

    // ── LUI (pass-through operand_b) ─────────────────────────────────
    apply_and_check(ALU_LUI, 32'hDEADBEEF,   32'hABCD1234,  32'hABCD1234,   32'hXXXXXXXX,  34);
    apply_and_check(ALU_LUI, 32'h00000000,   32'hFFFFF000,  32'hFFFFF000,   32'hXXXXXXXX,  35);

    // ── Summary ──────────────────────────────────────────────────────
    $display("─────────────────────────────────");
    $display("RESULTS: %0d passed, %0d failed", pass_count, fail_count);
    if (fail_count == 0)
      $display("ALL TESTS PASSED");
    else
      $display("SOME TESTS FAILED");
    $display("─────────────────────────────────");
    $finish;
  end

endmodule
