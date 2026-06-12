"""
verilog_refiner.py

Iterative LLM-based Verilog generation with spaCy intent matching as stopping condition.

Usage:
    python verilog_refiner.py --spec "Create a 4-bit up counter with synchronous reset"

Requirements:
    pip install openai spacy
    python -m spacy download en_core_web_md
"""

import argparse
import os
import re
import openai

import spacy

# ── Config ────────────────────────────────────────────────────────────────────
MAX_ROUNDS        = 5
GOOD_ENOUGH       = 0.60   # 60% semantic coverage → accept
GIVE_UP_DELTA     = 0.05   # if improvement < 5% for this many consecutive rounds → give up
GIVE_UP_PATIENCE  = 2
MODEL             = "gpt-4"

nlp = spacy.load("en_core_web_md")

# ── Intent Extraction ─────────────────────────────────────────────────────────

def extract_intent(spec: str) -> list[str]:
    """
    Extract key concepts from the user's natural language spec.
    Returns a list of lemmatised concept strings (verbs + nouns + numbers).
    """
    doc = nlp(spec)
    concepts = []

    for token in doc:
        # action verbs: "count", "reset", "shift", "detect", "output", "enable"
        if token.pos_ == "VERB" and not token.is_stop:
            concepts.append(token.lemma_.lower())
        # important nouns: "clock", "reset", "counter", "bit", "edge"
        elif token.pos_ in ("NOUN", "PROPN") and not token.is_stop:
            concepts.append(token.lemma_.lower())

    # also grab numeric tokens like "4-bit", "8", "16"
    for ent in doc.ents:
        if ent.label_ in ("CARDINAL", "QUANTITY"):
            concepts.append(ent.text.lower())

    # deduplicate while preserving order
    seen = set()
    unique = []
    for c in concepts:
        if c not in seen:
            seen.add(c)
            unique.append(c)

    return unique


# ── Semantic Scorer ───────────────────────────────────────────────────────────

def score_verilog(verilog_code: str, intent_concepts: list[str]) -> tuple[float, list[str], list[str]]:
    """
    Compare generated Verilog against intent concepts using spaCy word vectors.
    Returns (score 0-1, matched_concepts, missed_concepts).
    """
    # tokenise the verilog — strip punctuation/operators, keep identifiers
    tokens_raw = re.findall(r'[a-zA-Z_][a-zA-Z0-9_]*', verilog_code)
    verilog_words = list(set(t.lower() for t in tokens_raw))

    matched   = []
    missed    = []

    for concept in intent_concepts:
        concept_doc = nlp(concept)
        if not concept_doc.has_vector:
            # fall back to exact substring match for OOV tokens
            if any(concept in w for w in verilog_words):
                matched.append(concept)
            else:
                missed.append(concept)
            continue

        # first try exact substring match (catches "counter" in "count", "4" in "4'b0000")
        if any(concept in w or w in concept for w in verilog_words):
            matched.append(concept)
            continue

        # then try semantic similarity
        best_sim = 0.0
        for word in verilog_words:
            word_doc = nlp(word)
            if word_doc.has_vector:
                sim = concept_doc.similarity(word_doc)
                if sim > best_sim:
                    best_sim = sim

        # lowered threshold: 0.55 cosine similarity counts as a match
        if best_sim >= 0.55:
            matched.append(concept)
        else:
            missed.append(concept)

    score = len(matched) / len(intent_concepts) if intent_concepts else 0.0
    return score, matched, missed


# ── LLM Calls ────────────────────────────────────────────────────────────────

def generate_verilog(spec: str, feedback: str | None = None) -> str:
    """Call OpenAI to generate Verilog. Optionally pass previous feedback."""
    system_prompt = (
        "You are an expert RTL/Verilog engineer. "
        "When given a hardware specification, output ONLY valid synthesisable Verilog or SystemVerilog. "
        "Do not include explanations, markdown fences, or comments outside the module."
    )

    user_content = f"Specification:\n{spec}"
    if feedback:
        user_content += f"\n\nPrevious attempt had issues. Please fix the following:\n{feedback}"

    client = openai.OpenAI(api_key=os.environ["OPENAI_API_KEY"])
    response = client.chat.completions.create(
        model=MODEL,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user",   "content": user_content},
        ],
        temperature=0.2,
    )
    return response.choices[0].message.content.strip()


def build_feedback(missed_concepts: list[str], score: float) -> str:
    """Generate a feedback string to send back to the LLM."""
    missed_str = ", ".join(missed_concepts) if missed_concepts else "none identified"
    return (
        f"The current implementation only addresses {score*100:.1f}% of the required behaviour. "
        f"The following concepts appear to be missing or not clearly implemented: {missed_str}. "
        f"Please revise the Verilog to fully address these."
    )


# ── Main Loop ─────────────────────────────────────────────────────────────────

def refine(spec: str, verbose: bool = True) -> dict:
    """
    Run the iterative refinement loop.
    Returns a dict with the best Verilog, its score, and how many rounds it took.
    """
    intent = extract_intent(spec)
    if verbose:
        print(f"\n[Intent] Extracted {len(intent)} concepts: {intent}\n")

    best_code      = ""
    best_score     = 0.0
    scores         = []
    feedback       = None
    no_improve_ctr = 0

    for round_num in range(1, MAX_ROUNDS + 1):
        if verbose:
            print(f"── Round {round_num}/{MAX_ROUNDS} ──")

        code  = generate_verilog(spec, feedback)
        score, matched, missed = score_verilog(code, intent)
        scores.append(score)

        if verbose:
            print(f"  Score   : {score*100:.1f}%")
            print(f"  Matched : {matched}")
            print(f"  Missed  : {missed}\n")

        if score > best_score:
            best_score = score
            best_code  = code

        # ── Stopping conditions ──────────────────────────────────────────
        if score >= GOOD_ENOUGH:
            if verbose:
                print(f"✓ Good enough at round {round_num} ({score*100:.1f}% ≥ {GOOD_ENOUGH*100:.0f}%)")
            break

        if round_num >= 2:
            delta = scores[-1] - scores[-2]
            if delta < GIVE_UP_DELTA:
                no_improve_ctr += 1
            else:
                no_improve_ctr = 0

            if no_improve_ctr >= GIVE_UP_PATIENCE:
                if verbose:
                    print(f"✗ Giving up — improvement stalled for {GIVE_UP_PATIENCE} rounds.")
                break

        feedback = build_feedback(missed, score)

    return {
        "verilog"    : best_code,
        "score"      : best_score,
        "rounds"     : round_num,
        "scores"     : scores,
        "intent"     : intent,
    }


# ── CLI ───────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Iterative Verilog LLM refiner")
    parser.add_argument("--spec", type=str, required=True, help="Natural language hardware specification")
    parser.add_argument("--out",  type=str, default="output.sv", help="Output file for best Verilog")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    result = refine(args.spec, verbose=not args.quiet)

    with open(args.out, "w") as f:
        f.write(result["verilog"])

    print(f"\nBest score : {result['score']*100:.1f}%")
    print(f"Rounds used: {result['rounds']}")
    print(f"Saved to   : {args.out}")
    print(f"\nScore progression: {[f'{s*100:.1f}%' for s in result['scores']]}")
