`timescale 1ns / 1ps

module test_MCycle_post_synth #(parameter SIGNED_CYCLES = 16);
    reg CLK = 0;
    reg RESET = 1;
    reg Start = 0;
    reg [1:0] MCycleOp = 0;
    reg [31:0] Operand1 = 0;
    reg [31:0] Operand2 = 0;
    wire [31:0] Result1;
    wire [31:0] Result2;
    wire Busy;
    reg completion_pending = 0;
    reg [31:0] random_state = 32'h00003207;
    reg [31:0] random_a, random_b;
    reg [1:0] random_op;
    reg [31:0] edge_values [0:8];
    integer busy_cycles = 0;
    integer checks = 0;
    integer i, j;

`ifdef MCYCLE_RTL
    MCycle #(.width(32)) dut(
`else
    MCycle dut(
`endif
        .CLK(CLK), .RESET(RESET), .Start(Start), .MCycleOp(MCycleOp),
        .Operand1(Operand1), .Operand2(Operand2),
        .Result1(Result1), .Result2(Result2), .Busy(Busy)
    );

    always #5 CLK = ~CLK;
    always @(posedge CLK)
        if (Busy === 1'b1) busy_cycles = busy_cycles + 1;

    function [31:0] next_random;
        input [31:0] previous;
        reg [31:0] value;
        begin
            value = previous ^ (previous << 13);
            value = value ^ (value >> 17);
            next_random = value ^ (value << 5);
        end
    endfunction

    task run_op;
        input [1:0] op;
        input [31:0] a, b;
        input hold;
        reg signed [63:0] signed_a, signed_b;
        reg [63:0] product;
        reg [31:0] expected1, expected2;
        integer expected_cycles;
        begin
            signed_a = {{32{a[31]}}, a};
            signed_b = {{32{b[31]}}, b};
            case (op)
                2'b00: begin
                    product = signed_a * signed_b;
                    expected1 = product[31:0];
                    expected2 = product[63:32];
                    expected_cycles = SIGNED_CYCLES;
                end
                2'b01: begin
                    product = {32'd0, a} * {32'd0, b};
                    expected1 = product[31:0];
                    expected2 = product[63:32];
                    expected_cycles = 32;
                end
                2'b10: begin
                    if (b == 0) $fatal(1, "Zero divisor in evaluation");
                    expected1 = signed_a / signed_b;
                    expected2 = signed_a % signed_b;
                    expected_cycles = 32;
                end
                2'b11: begin
                    if (b == 0) $fatal(1, "Zero divisor in evaluation");
                    expected1 = a / b;
                    expected2 = a % b;
                    expected_cycles = 32;
                end
            endcase
            @(negedge CLK);
            MCycleOp = op;
            Operand1 = a;
            Operand2 = b;
            busy_cycles = 0;
            Start = 1;
            #1;
            if (completion_pending) begin
                if (Busy !== 1'b0) $fatal(1, "Missing completion interval");
                @(posedge CLK);
                #1;
                if (Busy !== 1'b1) $fatal(1, "Back-to-back operation not accepted");
            end
            else if (Busy !== 1'b1)
                $fatal(1, "Busy did not assert from idle");
            begin : completion_watchdog
                fork
                    begin
                        wait (Busy === 1'b0);
                        disable completion_watchdog;
                    end
                    begin
                        repeat (expected_cycles + 4) @(posedge CLK);
                        #2;
                        $fatal(1, "Operation stalled: completed_checks=%0d op=%b a=%h b=%h Busy=%b busy_cycles=%0d expected_cycles=%0d",
                            checks, op, a, b, Busy, busy_cycles, expected_cycles);
                    end
                join
            end
            #1;
            checks = checks + 1;
            if (Result1 !== expected1 || Result2 !== expected2 || busy_cycles != expected_cycles)
                $fatal(1, "op=%b a=%h b=%h result=%h:%h expected=%h:%h cycles=%0d expected_cycles=%0d",
                    op, a, b, Result2, Result1, expected2, expected1, busy_cycles, expected_cycles);
            if (checks % 100 == 0)
                $display("PROGRESS: %0d result checks completed at %0t", checks, $time);
            completion_pending = hold;
            if (!hold) begin
                Start = 0;
                @(posedge CLK);
                #1;
                if (Busy !== 1'b0 || Result1 !== expected1 || Result2 !== expected2)
                    $fatal(1, "Idle result retention failed");
            end
        end
    endtask

    task check_idle;
        reg [31:0] saved1, saved2;
        integer step;
        begin
            saved1 = Result1;
            saved2 = Result2;
            for (step = 0; step < 5; step = step + 1) begin
                @(negedge CLK);
                Operand1 = ~Operand1;
                Operand2 = Operand2 + 1;
                MCycleOp = MCycleOp + 1'b1;
                @(posedge CLK);
                #1;
                if (Busy !== 1'b0 || Result1 !== saved1 || Result2 !== saved2)
                    $fatal(1, "Results changed while idle");
            end
        end
    endtask

    task reset_multiply;
        input integer completed_iterations;
        begin
            @(negedge CLK);
            MCycleOp = 2'b00;
            Operand1 = 32'h80000000;
            Operand2 = 32'h7fffffff;
            Start = 1;
            #1;
            if (Busy !== 1'b1) $fatal(1, "Reset test did not start");
            repeat (completed_iterations) @(posedge CLK);
            #1;
            if (Busy !== 1'b1) $fatal(1, "Reset test missed computation");
            RESET = 1;
            #1;
            if (Busy !== 1'b0) $fatal(1, "Busy did not clear during reset");
            @(posedge CLK);
            #1;
            Start = 0;
            RESET = 0;
            completion_pending = 0;
            @(posedge CLK);
            #1;
            if (Busy !== 1'b0) $fatal(1, "Busy not idle after reset");
            run_op(2'b00, 32'h80000000, 32'hffffffff, 1'b0);
            run_op(2'b11, 32'hffffffff, 32'd2, 1'b0);
        end
    endtask

    initial begin
        if (SIGNED_CYCLES != 16 && SIGNED_CYCLES != 64)
            $fatal(1, "Expected either baseline or Booth cycle count");
        edge_values[0] = 0;
        edge_values[1] = 1;
        edge_values[2] = 32'hffffffff;
        edge_values[3] = 2;
        edge_values[4] = 32'hfffffffe;
        edge_values[5] = 32'h80000000;
        edge_values[6] = 32'h7fffffff;
        edge_values[7] = 32'h55555555;
        edge_values[8] = 32'haaaaaaaa;
        #201;
        RESET = 0;
        for (i = 0; i < 9; i = i + 1)
            for (j = 0; j < 9; j = j + 1)
                run_op(2'b00, edge_values[i], edge_values[j], 1'b0);
        check_idle;
        for (i = 0; i < 32; i = i + 1) begin
            run_op(2'b00, 32'h80000000, 32'd1 << i, 1'b1);
            run_op(2'b00, 32'h7fffffff, -(32'd1 << i), 1'b0);
        end
        for (i = 0; i < 1000; i = i + 1) begin
            random_state = next_random(random_state);
            random_a = random_state;
            random_state = next_random(random_state);
            random_b = random_state;
            run_op(2'b00, random_a, random_b, 1'b1);
        end
        run_op(2'b00, 32'h80000000, 32'h80000000, 1'b0);
        for (i = 0; i < 4; i = i + 1)
            for (j = 0; j < 4; j = j + 1) begin
                run_op(i, 32'h80000000, 32'hffffffff, 1'b1);
                run_op(j, 32'h7fffffff, 32'hffffffff, 1'b1);
            end
        run_op(2'b00, 1, 1, 1'b0);
        for (i = 0; i < 500; i = i + 1) begin
            random_state = next_random(random_state);
            random_op = random_state[1:0];
            random_state = next_random(random_state);
            random_a = random_state;
            random_state = next_random(random_state);
            random_b = random_state;
            if (random_op[1] && random_b == 0) random_b = 1;
            run_op(random_op, random_a, random_b, 1'b1);
        end
        run_op(2'b00, 1, 1, 1'b0);
        reset_multiply(1);
        reset_multiply(SIGNED_CYCLES/2);
        reset_multiply(SIGNED_CYCLES-1);
        check_idle;
        $display("SIGNED MULTIPLICATION: busy_cycles=%0d", SIGNED_CYCLES);
`ifdef MCYCLE_RTL
        $display("ALL RTL EVALUATION TESTS PASSED (%0d result checks)", checks);
`else
        $display("ALL POST-SYNTHESIS TESTS PASSED (%0d result checks)", checks);
`endif
        $finish;
    end

    initial begin
        #2_000_000;
        $fatal(1, "MCycle evaluation timeout");
    end
endmodule
