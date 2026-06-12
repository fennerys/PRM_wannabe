"""
test_refiner.py

Unit tests for verilog_refiner.py that do NOT call the OpenAI API.
Tests the intent extractor and semantic scorer in isolation.

Run with:
    python test_refiner.py
"""

import unittest
from verilog_refiner import extract_intent, score_verilog, build_feedback

# ── Sample Verilog snippets for testing ──────────────────────────────────────

COUNTER_VERILOG = """
module counter_4bit (
    input  wire clk,
    input  wire reset,
    output reg [3:0] count
);
    always @(posedge clk) begin
        if (reset)
            count <= 4'b0000;
        else
            count <= count + 1;
    end
endmodule
"""

EMPTY_VERILOG = """
module empty(input clk);
endmodule
"""

PARTIAL_VERILOG = """
module partial (
    input wire clk,
    input wire reset
);
    // clock and reset present but no counter logic
endmodule
"""


# ── Tests ─────────────────────────────────────────────────────────────────────

class TestIntentExtraction(unittest.TestCase):

    def test_extracts_verbs(self):
        spec = "Create a 4-bit up counter with synchronous reset"
        intent = extract_intent(spec)
        print(f"\n[intent] {intent}")
        self.assertTrue(any("count" in c or "creat" in c for c in intent),
                        "Should extract action verb")

    def test_extracts_nouns(self):
        spec = "Design a shift register with clock and enable"
        intent = extract_intent(spec)
        print(f"\n[intent] {intent}")
        self.assertTrue(any("register" in c or "shift" in c for c in intent))
        self.assertTrue(any("clock" in c or "clk" in c or "enable" in c for c in intent))

    def test_extracts_numbers(self):
        spec = "Implement an 8-bit adder"
        intent = extract_intent(spec)
        print(f"\n[intent] {intent}")
        self.assertTrue(any("8" in c for c in intent), "Should extract numeric constraint")

    def test_deduplication(self):
        spec = "count up count down counter"
        intent = extract_intent(spec)
        # 'count' should only appear once
        count_occurrences = sum(1 for c in intent if c == "count")
        self.assertEqual(count_occurrences, 1)


class TestSemanticScorer(unittest.TestCase):

    def test_good_counter_scores_high(self):
        spec = "Create a 4-bit up counter with synchronous reset"
        intent = extract_intent(spec)
        score, matched, missed = score_verilog(COUNTER_VERILOG, intent)
        print(f"\n[score/good] {score*100:.1f}% | matched={matched} | missed={missed}")
        self.assertGreater(score, 0.5, "Complete counter should score above 50%")

    def test_empty_module_scores_low(self):
        spec = "Create a 4-bit up counter with synchronous reset"
        intent = extract_intent(spec)
        score, matched, missed = score_verilog(EMPTY_VERILOG, intent)
        print(f"\n[score/empty] {score*100:.1f}% | matched={matched} | missed={missed}")
        self.assertLess(score, 0.5, "Empty module should score below 50%")

    def test_partial_scores_in_between(self):
        spec = "Create a 4-bit up counter with synchronous reset"
        intent = extract_intent(spec)
        score_good,    _, _ = score_verilog(COUNTER_VERILOG, intent)
        score_partial, _, _ = score_verilog(PARTIAL_VERILOG, intent)
        score_empty,   _, _ = score_verilog(EMPTY_VERILOG,   intent)
        print(f"\n[score comparison] good={score_good:.2f} partial={score_partial:.2f} empty={score_empty:.2f}")
        self.assertGreater(score_good, score_partial)
        self.assertGreaterEqual(score_partial, score_empty)

    def test_returns_matched_and_missed_lists(self):
        intent = ["clock", "reset", "count"]
        score, matched, missed = score_verilog(COUNTER_VERILOG, intent)
        self.assertIsInstance(matched, list)
        self.assertIsInstance(missed,  list)
        self.assertEqual(len(matched) + len(missed), len(intent))


class TestFeedbackBuilder(unittest.TestCase):

    def test_feedback_mentions_missed(self):
        missed = ["shift", "enable", "8-bit"]
        feedback = build_feedback(missed, 0.30)
        print(f"\n[feedback] {feedback}")
        for concept in missed:
            self.assertIn(concept, feedback)

    def test_feedback_mentions_score(self):
        feedback = build_feedback(["reset"], 0.35)
        self.assertIn("35.0%", feedback)


# ── Runner ────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    unittest.main(verbosity=2)
