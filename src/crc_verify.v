//==========================================================================
// ГЛАВНЫЙ МОДУЛЬ ВЕРХНЕГО УРОВНЯ (TOP MODULE) — crc_verify.v
//==========================================================================

module crc_verify (
    input  wire        clk,        // Системный клок ПЛИС
    input  wire        rst_n,      // Асинхронный сброс
    input  wire        rx_data,    // Входные данные телеметрии с пина ПЛИС
    input  wire        bit_clk_en, // Строб битовой синхронизации (32 кГц)
    output wire        err         // Финальный флаг ошибки на выходе всей системы
);

    // Внутренние сигналы управления кадрированием (из owon_rx_core)
    reg [5:0]  bit_cnt;
    reg [54:0] shift_reg;
    reg        gen_startIn;
    reg        gen_endIn;
    reg        gen_validIn;
    
    localparam FRAME_LENGTH = 55;

    // Автомат выделения кадра (Счетчик 1..55)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt     <= 6'd0;
            shift_reg   <= 55'd0;
            gen_startIn <= 1'b0;
            gen_endIn   <= 1'b0;
            gen_validIn <= 1'b0;
        end else if (bit_clk_en) begin
            shift_reg   <= {shift_reg[53:0], rx_data};
            
            if (bit_cnt >= FRAME_LENGTH)
                bit_cnt <= 6'd1;
            else
                bit_cnt <= bit_cnt + 6'd1;
                
            gen_startIn <= (bit_cnt == 6'd1);
            gen_endIn   <= (bit_cnt == 6'd55);
            gen_validIn <= (bit_cnt <= 6'd55);
        end else begin
            gen_startIn <= 1'b0;
            gen_endIn   <= 1'b0;
        end
    end

    // Провода для соединения блоков между собой
    wire [47:0] hamming_decoded_data;
    wire        hamming_double_error;
    wire        crc_failed;

    // 1. Подключение декодера Хэмминга (SEC-DED)
    hamming_sec_ded_decoder u_hamming (
        .frame_in(shift_reg),
        .data_out(hamming_decoded_data),
        .double_error(hamming_double_error)
    );

        // 2. Подключение нашего кастомного RTL-детектора CRC-32
    custom_crc32_detector u_crc32 (
        .clk(clk),
        .rst_n(rst_n),
        .dataIn(hamming_decoded_data[47]), // ИСПРАВЛЕНО: выбираем 1 бит из 48-битной шины
        .startIn(gen_startIn),
        .endIn(gen_endIn),
        .validIn(gen_validIn),
        .err(crc_failed)
    );


    // Финальный выход схемы: ошибка фиксируется, если сбоит или Хэмминг, или CRC
    assign err = hamming_double_error | crc_failed;

endmodule


