`timescale 1ns / 1ps

module test_Wrapper_Demo;
    reg CLK = 0;
    reg RESET = 1;
    reg [15:0] DIP = 0;
    wire [7:0] LED_OUT;
    wire [31:0] SEVENSEGHEX;
    reg [31:0] operands_a [0:15];
    reg [31:0] operands_b [0:15];
    integer retired = 0;
    integer busy_edges = 0;
    integer views_checked = 0;
    integer suites_checked = 0;
    integer baseline_retired;
    integer k;

    Wrapper dut(
        .DIP(DIP), .PB(3'd0), .LED_OUT(LED_OUT), .SEVENSEGHEX(SEVENSEGHEX),
        .UART_TX_ready(1'b1), .UART_RX(8'd0), .UART_RX_valid(1'b0),
        .ACCEL_Data(32'd0), .ACCEL_DReady(1'b0), .RESET(RESET), .CLK(CLK)
    );

    always #5 CLK = ~CLK;

    function integer operation;
        input integer index;
        begin
            operation = index < 6 ? 1 : index < 12 ? 2 : 3;
        end
    endfunction

    function [31:0] reference_result;
        input integer index;
        reg signed [63:0] a, b;
        reg [63:0] product;
        begin
            a = {{32{operands_a[index][31]}}, operands_a[index]};
            b = {{32{operands_b[index][31]}}, operands_b[index]};
            case (operation(index))
                1: begin
                    product = a * b;
                    reference_result = product[31:0];
                end
                2: reference_result = a / b;
                3: reference_result = operands_a[index] / operands_b[index];
            endcase
        end
    endfunction

    always @(posedge CLK) begin : monitor
        reg [31:0] stalled_pc;
        integer expected_cycles;
        if (RESET) busy_edges = 0;
        else if (dut.RV1.Busy === 1'b1) begin
            stalled_pc = dut.PC;
            if (dut.Instr[6:0] !== 7'h33 || dut.Instr[31:25] !== 7'h01)
                $fatal(1, "Busy asserted outside an M instruction");
            if (dut.RV1.WE !== 0 || dut.RV1.WE_PC !== 0 ||
                dut.MemWrite_out !== 0 || dut.MemRead !== 0)
                $fatal(1, "Side effect enabled during multicycle stall");
            busy_edges = busy_edges + 1;
            #1;
            if (!RESET && dut.PC !== stalled_pc)
                $fatal(1, "PC advanced while Busy");
        end
        else if (dut.RV1.Busy === 1'b0 && busy_edges > 0) begin
            expected_cycles = dut.Instr[14:12] == 0 ? 16 : 32;
            if (busy_edges != expected_cycles)
                $fatal(1, "Busy edges=%0d expected=%0d", busy_edges, expected_cycles);
            if (dut.Instr[6:0] !== 7'h33 || dut.Instr[31:25] !== 7'h01 ||
                (dut.Instr[14:12] != 0 && dut.Instr[14:12] != 4 && dut.Instr[14:12] != 5))
                $fatal(1, "Unexpected instruction at M retirement");
            if (dut.RV1.WE !== 1 || dut.RV1.WE_PC !== 1)
                $fatal(1, "CPU failed to resume at M retirement");
            retired = retired + 1;
            busy_edges = 0;
        end
        else if (dut.RV1.Busy !== 1'b0)
            $fatal(1, "Unknown Busy signal");
    end

    task start_suite;
        input integer failed_case;
        integer attempts;
        begin
            @(negedge CLK);
            RESET = 1;
            DIP = 0;
            repeat (3) @(negedge CLK);
            dut.DMEM[13*6+3] = reference_result(13) ^ (failed_case == 13 ? 32'd1 : 32'd0);
            baseline_retired = retired;
            RESET = 0;
            attempts = 0;
            while (dut.DMEM[97] !== 0 && attempts < 100) begin
                @(negedge CLK);
                attempts = attempts + 1;
            end
            if (dut.DMEM[97] !== 0) $fatal(1, "Program did not clear suite_done on reset");
        end
    endtask

    task finish_suite;
        input integer failed_case;
        integer attempts, index;
        reg [31:0] expected;
        begin
            attempts = 0;
            while (dut.DMEM[97] !== 1 && attempts < 6000) begin
                @(negedge CLK);
                attempts = attempts + 1;
            end
            if (dut.DMEM[97] !== 1) $fatal(1, "Demo suite timeout");
            if (retired - baseline_retired != 16)
                $fatal(1, "Demo did not execute exactly 16 M instructions");
            for (index = 0; index < 16; index = index + 1) begin
                expected = reference_result(index);
                if (dut.DMEM[index*6] !== operation(index) ||
                    dut.DMEM[index*6+1] !== operands_a[index] ||
                    dut.DMEM[index*6+2] !== operands_b[index])
                    $fatal(1, "Case %0d input table differs from independent reference", index);
                if (dut.DMEM[index*6+3] !== (expected ^ (failed_case == index ? 32'd1 : 32'd0)))
                    $fatal(1, "Case %0d expected table value is wrong", index);
                if (dut.DMEM[index*6+4] !== expected)
                    $fatal(1, "Case %0d actual=%h expected=%h", index, dut.DMEM[index*6+4], expected);
                if (dut.DMEM[index*6+5] !== (index == failed_case ? 32'd0 : 32'd1))
                    $fatal(1, "Case %0d pass flag incorrect", index);
            end
            if (dut.DMEM[96] !== (failed_case < 0 ? 32'd1 : 32'd0))
                $fatal(1, "Overall pass flag incorrect");
            suites_checked = suites_checked + 1;
        end
    endtask

    task check_view;
        input integer index, view, failed_case;
        input [15:0] upper_switches;
        reg [31:0] expected_display;
        reg [7:0] expected_led;
        integer retired_before;
        begin
            case (view)
                0: expected_display = reference_result(index);
                1: expected_display = operands_a[index];
                2: expected_display = operands_b[index];
                3: expected_display = reference_result(index) ^ (failed_case == index ? 32'd1 : 32'd0);
            endcase
            expected_led = (failed_case < 0 ? 8'h80 : 0) |
                           (index != failed_case ? 8'h40 : 0) |
                           (operation(index) << 4) | index;
            @(negedge CLK);
            DIP = (upper_switches & 16'hFFC0) | (view << 4) | index;
            retired_before = retired;
            repeat (80) @(negedge CLK);
            if (SEVENSEGHEX !== expected_display || LED_OUT !== expected_led)
                $fatal(1, "Case %0d view %0d display=%h expected=%h LED=%h expected=%h",
                       index, view, SEVENSEGHEX, expected_display, LED_OUT, expected_led);
            if (retired != retired_before)
                $fatal(1, "Display loop unexpectedly repeated arithmetic tests");
            views_checked = views_checked + 1;
        end
    endtask

    task all_views;
        input integer failed_case;
        integer index, view;
        begin
            for (index = 0; index < 16; index = index + 1)
                for (view = 0; view < 4; view = view + 1)
                    check_view(index, view, failed_case, 0);
        end
    endtask

    initial begin
        operands_a[0] = 7; operands_b[0] = 3;
        operands_a[1] = -7; operands_b[1] = 3;
        operands_a[2] = -7; operands_b[2] = -3;
        operands_a[3] = 0; operands_b[3] = 123;
        operands_a[4] = 32'h80000000; operands_b[4] = -1;
        operands_a[5] = 546540564; operands_b[5] = 456546541;
        operands_a[6] = 7; operands_b[6] = 3;
        operands_a[7] = -7; operands_b[7] = 3;
        operands_a[8] = 7; operands_b[8] = -3;
        operands_a[9] = -7; operands_b[9] = -3;
        operands_a[10] = 0; operands_b[10] = 3;
        operands_a[11] = 32'h80000000; operands_b[11] = -1;
        operands_a[12] = 7; operands_b[12] = 3;
        operands_a[13] = 32'hFFFFFFFF; operands_b[13] = 3;
        operands_a[14] = 32'h80000000; operands_b[14] = 2;
        operands_a[15] = 5; operands_b[15] = 7;
        start_suite(-1);
        finish_suite(-1);
        all_views(-1);
        check_view(5, 0, -1, 16'hFFC0);
        start_suite(-1);
        finish_suite(-1);
        check_view(7, 0, -1, 0);
        start_suite(13);
        finish_suite(13);
        all_views(13);
        start_suite(-1);
        finish_suite(-1);
        check_view(13, 0, -1, 0);
        start_suite(-1);
        wait (dut.RV1.Busy === 1);
        repeat (3) @(negedge CLK);
        start_suite(-1);
        finish_suite(-1);
        all_views(-1);
        $display("ALL FPGA DEMO TESTS PASSED (%0d suites, %0d case/view checks)", suites_checked, views_checked);
        $finish;
    end

    initial begin
        #2_000_000;
        $fatal(1, "Demo testbench timeout");
    end
endmodule
