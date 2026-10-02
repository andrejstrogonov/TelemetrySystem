module ecc_logging (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [47:0]  sample_crc_in,
    input  wire         data_valid,
    input  wire         read_en,
    input  wire [8:0]   read_addr,
    input  wire [15:0]  reference_level,
    output wire [47:0]  data_out,
    output wire         data_out_valid,
    output wire         single_error_corrected,
    output wire         double_error_detected,
    output wire         anomaly_detected
);

    ecc_ring_buffer u_ring_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(sample_crc_in),
        .data_valid(data_valid),
        .read_en(read_en),
        .read_addr(read_addr),
        .data_out(data_out),
        .data_out_valid(data_out_valid),
        .single_error_corrected(single_error_corrected),
        .double_error_detected(double_error_detected)
    );

    anomaly_detector u_anomaly_detector (
        .sample_value(sample_crc_in[15:0]),
        .reference_level(reference_level),
        .anomaly_detected(anomaly_detected)
    );

endmodule

