module anomaly_detector (
    input  wire [15:0] sample_value,
    input  wire [15:0] reference_level,
    output wire        anomaly_detected
);

    wire signed [16:0] sample_extended = {sample_value[15], sample_value};
    wire signed [16:0] reference_extended = {reference_level[15], reference_level};
    wire signed [16:0] delta = sample_extended - reference_extended;
    wire [16:0] absolute_delta = delta[16] ? -delta : delta;
    wire [16:0] absolute_reference = reference_extended[16]
        ? -reference_extended
        : reference_extended;
    wire [23:0] scaled_delta = absolute_delta * 24'd100;
    wire [23:0] scaled_reference = absolute_reference * 24'd30;

    assign anomaly_detected = scaled_delta > scaled_reference;

endmodule