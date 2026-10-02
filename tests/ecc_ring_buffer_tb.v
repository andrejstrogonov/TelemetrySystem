`timescale 1ns/1ps

module ecc_ring_buffer_tb;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [47:0] data_in = 48'd0;
    reg data_valid = 1'b0;
    reg read_en = 1'b0;
    reg [1:0] read_addr = 2'd0;
    wire [47:0] data_out;
    wire data_out_valid;
    wire single_error_corrected;
    wire double_error_detected;

    ecc_ring_buffer #(.DEPTH_WIDTH(2)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .data_valid(data_valid),
        .read_en(read_en),
        .read_addr(read_addr),
        .data_out(data_out),
        .data_out_valid(data_out_valid),
        .single_error_corrected(single_error_corrected),
        .double_error_detected(double_error_detected)
    );

    always #5 clk = ~clk;

    task check_read;
        input [47:0] expected_data;
        input expected_corrected;
        input expected_uncorrectable;
        begin
            @(negedge clk);
            read_en = 1'b1;
            read_addr = 2'd0;
            @(posedge clk);
            #1;
            if (!data_out_valid || data_out !== expected_data ||
                single_error_corrected !== expected_corrected ||
                double_error_detected !== expected_uncorrectable) begin
                $display("FAIL read: data=%h valid=%b corrected=%b uncorrectable=%b raw=%h syndrome=%d overall=%b",
                         data_out, data_out_valid, single_error_corrected, double_error_detected,
                         dut.word_to_decode, dut.syndrome, dut.overall_mismatch);
                $finish(1);
            end
            @(negedge clk);
            read_en = 1'b0;
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        @(negedge clk);
        read_en = 1'b1;
        read_addr = 2'd0;
        @(posedge clk);
        #1;
        if (data_out_valid) begin
            $display("FAIL unwritten address reported valid");
            $finish(1);
        end

        @(negedge clk);
        read_en = 1'b0;
        data_in = 48'hA5C3_19E7_42D6;
        data_valid = 1'b1;
        @(negedge clk);
        data_valid = 1'b0;
        check_read(48'hA5C3_19E7_42D6, 1'b0, 1'b0);

        dut.ram_matrix[0][12] = ~dut.ram_matrix[0][12];
        check_read(48'hA5C3_19E7_42D6, 1'b1, 1'b0);

        dut.ram_matrix[0][20] = ~dut.ram_matrix[0][20];
        check_read(48'd0, 1'b0, 1'b1);

        $display("PASS ecc_ring_buffer_tb");
        $finish(0);
    end
endmodule