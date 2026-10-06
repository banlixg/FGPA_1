`timescale 1ns/1ps
module tb_team_frame_latch;
reg clk;
reg rst_n;
reg frame_accept;
reg [1:0] frame_id_in;
wire [1:0] frame_id_out;
wire frame_valid;
wire accepted_pulse;
integer checks;
integer failures;
integer done;
integer result_file;
integer inject_fail;

team_frame_latch dut (
    .clk(clk), .rst_n(rst_n), .frame_accept(frame_accept),
    .frame_id_in(frame_id_in), .frame_id_out(frame_id_out),
    .frame_valid(frame_valid), .accepted_pulse(accepted_pulse)
);
initial clk = 1'b0;
always #10 clk = ~clk;

task check;
    input [1:0] expected_id;
    input expected_valid;
    input expected_pulse;
    begin
        checks = checks + 1;
        if (frame_id_out !== expected_id ||
            frame_valid !== expected_valid ||
            accepted_pulse !== expected_pulse) begin
            failures = failures + 1;
            $display("FAIL check=%0d t=%0t id=%0d valid=%b pulse=%b expected=%0d/%b/%b",
                checks, $time, frame_id_out, frame_valid, accepted_pulse,
                expected_id, expected_valid, expected_pulse);
        end else
            $display("PASS check=%0d t=%0t id=%0d valid=%b pulse=%b",
                checks, $time, frame_id_out, frame_valid, accepted_pulse);
    end
endtask

// Inputs change on falling edges. Check after the next rising edge.
task step;
    input accept;
    input [1:0] new_id;
    input [1:0] expected_id;
    input expected_valid;
    input expected_pulse;
    begin
        @(negedge clk);
        frame_accept = accept;
        frame_id_in = new_id;
        @(posedge clk); #1;
        check(expected_id, expected_valid, expected_pulse);
    end
endtask

initial begin
    checks = 0;
    failures = 0;
    done = 0;
    inject_fail = $test$plusargs("INJECT_FAIL");
    rst_n = 1'b0;
    frame_accept = 1'b0;
    frame_id_in = 2'd0;
    #1; check(2'd0, 1'b0, 1'b0);
    @(negedge clk); rst_n = 1'b1;
    step(1'b0, 2'd3, 2'd0, 1'b0, 1'b0);
    step(1'b1, 2'd1, 2'd1, 1'b1, 1'b1);
    step(1'b0, 2'd2, 2'd1, 1'b1, 1'b0);
    step(1'b1, 2'd2, 2'd2, 1'b1, 1'b1);
    step(1'b1, 2'd3, 2'd3, 1'b1, 1'b1);
    step(1'b0, 2'd0, 2'd3, 1'b1, 1'b0);
    #4; rst_n = 1'b0;
    #1; check(2'd0, 1'b0, 1'b0);
    @(negedge clk); rst_n = 1'b1;
    step(1'b1, 2'd0, 2'd0, 1'b1, 1'b1);
    step(1'b0, 2'd3, 2'd0, 1'b1, 1'b0);
    if (inject_fail) check(2'd1, 1'b1, 1'b0);
    result_file = $fopen("result.txt", "w");
    if (failures == 0) begin
        $display("ALL_PASS checks=%0d", checks);
        $fdisplay(result_file, "ALL_PASS checks=%0d", checks);
    end else begin
        $display("TEST_FAIL failures=%0d checks=%0d", failures, checks);
        $fdisplay(result_file, "TEST_FAIL failures=%0d checks=%0d", failures, checks);
    end
    $fclose(result_file);
    done = 1;
end
initial begin
    #1000;
    if (!done) begin
        $display("TEST_FAIL timeout");
        result_file = $fopen("result.txt", "w");
        $fdisplay(result_file, "TEST_FAIL timeout");
        $fclose(result_file);
    end
end
endmodule
