module rad_hard_fpga_top (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [31:0] data_in,
    input  wire        data_valid,

    input  wire        mcu1_heartbeat,

    output wire        mcu1_power_en,
    output wire        mcu1_reset_n,
    output wire        mcu2_power_en,
    output wire        mcu2_reset_n
);

    wire [31:0] ecc_data_buffered;
    wire        anomaly_detected;
    wire        mcu1_dead;
    
    // Внутренние провода для подключения диагностических флагов ECC
    wire        single_err_corr;
    wire        double_err_det;

    // Экземпляр кольцевого буфера
    ecc_ring_buffer u_ring_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .data_valid(data_valid),
        .data_out(ecc_data_buffered),
        .single_error_corrected(single_err_corr),
        .double_error_detected(double_err_det)
    );

    // Экземпляр детектора аномалий
    anomaly_detector u_anomaly_detector (
        .clk(clk),
        .rst_n(rst_n),
        .ecc_data_buffered(ecc_data_buffered),
        .anomaly_detected(anomaly_detected)
    );

    // Экземпляр арбитра микроконтроллеров
    mcu_arbiter u_mcu_arbiter (
        .clk(clk),
        .rst_n(rst_n),
        .mcu1_heartbeat(mcu1_heartbeat),
        .anomaly_detected(anomaly_detected),
        .mcu1_power_en(mcu1_power_en),
        .mcu1_reset_n(mcu1_reset_n),
        .mcu2_power_en(mcu2_power_en),
        .mcu2_reset_n(mcu2_reset_n),
        .mcu1_dead(mcu1_dead)
    );

endmodule

