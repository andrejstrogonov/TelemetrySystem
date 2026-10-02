`timescale 1ns/1ps

module anomaly_detector_tb;
    reg [15:0] sample_value = 16'd0;
    reg [15:0] reference_level = 16'd0;
    wire anomaly_detected;

    anomaly_detector dut (
        .sample_value(sample_value),
        .reference_level(reference_level),
        .anomaly_detected(anomaly_detected)
    );

    task check_result;
        input [15:0] sample;
        input [15:0] reference;
        input expected;
        begin
            sample_value = sample;
            reference_level = reference;
            #1;
            if (anomaly_detected !== expected) begin
                $display("FAIL anomaly: sample=%h reference=%h actual=%b expected=%b",
                         sample_value, reference_level, anomaly_detected, expected);
                $finish(1);
            end
        end
    endtask

    initial begin
        check_result(16'sd13000, 16'sd10000, 1'b0);
        check_result(16'sd13001, 16'sd10000, 1'b1);
        check_result(-16'sd13000, -16'sd10000, 1'b0);
        check_result(-16'sd13001, -16'sd10000, 1'b1);
        check_result(16'sd0, 16'sd0, 1'b0);
        check_result(16'sd1, 16'sd0, 1'b1);
        $display("PASS anomaly_detector_tb");
        $finish(0);
    end
endmodule