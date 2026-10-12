create_clock -name eval_clk -period 10.000 [get_ports CLK]
set_clock_uncertainty 0.200 [get_clocks eval_clk]
set_input_delay 2.000 -clock eval_clk [get_ports {RESET Start MCycleOp* Operand1* Operand2*}]
set_output_delay 2.000 -clock eval_clk [all_outputs]
