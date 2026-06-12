# PRM_wannabe

there's 2 parts:
    Pt. 1 (verilog_refiner.py and test_refiner.py) mostly covers the extration of intent so it uses spaCy to extract the 'intent' of a prompt and asks GPT-o4 to cough out the verilog and scores the output against extracted     intent. The output passes if it scores >= 60% and is sent into the machine again for a retry unless the jump in score is less that 5%; this is accoss a maximum of 5 rounds. The test refiner just checks the verilog          refiner's output (intent extraction, scoring leaderboard etc.) against the model answer which is hardwritten?coded? inside.

    Pt. 2 (prompt.txt, testbench.sv and ref.sv) sends a prompt file to the LLM (GPT-4o) and compiles the generated Verilog with iverilog. This sim is run against testbench.sv (35 test cases covering all RV32I ALU               operations). Can view ref for the right answers.
