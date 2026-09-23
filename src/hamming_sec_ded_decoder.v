//==========================================================================
// МОДУЛЬ ДЕКОДЕРА HAMMING SEC-DED (55, 48) ДЛЯ ПЛИС GOWIN
//==========================================================================
// Выполняет комбинаторную проверку синдромов, исправление одиночных сбоев
// и детектирование двойных (неисправимых) ошибок.

module hamming_sec_ded_decoder (
    input  wire [54:0] frame_in,      // Входной кадр (54 бита Хэмминга + 1 бит паритета)
    output reg  [47:0] data_out,      // Восстановленные 48 бит данных (payload + CRC)
    output reg         double_error   // Флаг обнаружения двойной ошибки (для инкремента TS)
);

    // Извлечение составляющих кадра
    wire [53:0] frame_54 = frame_in[54:1];
    wire        received_overall_parity = frame_in[0];

    // Вычисление 6 проверочных бит синдрома (для позиций 1, 2, 4, 8, 16, 32)
    wire [5:0] syndrome;
    
    assign syndrome[0] = frame_54[0]  ^ frame_54[2]  ^ frame_54[4]  ^ frame_54[6]  ^ frame_54[8]  ^ 
                         frame_54[10] ^ frame_54[12] ^ frame_54[14] ^ frame_54[16] ^ frame_54[18] ^ 
                         frame_54[20] ^ frame_54[22] ^ frame_54[24] ^ frame_54[26] ^ frame_54[28] ^ 
                         frame_54[30] ^ frame_54[32] ^ frame_54[34] ^ frame_54[36] ^ frame_54[38] ^ 
                         frame_54[40] ^ frame_54[42] ^ frame_54[44] ^ frame_54[46] ^ frame_54[48] ^ 
                         frame_54[50] ^ frame_54[52];

    assign syndrome[1] = frame_54[1]  ^ frame_54[2]  ^ frame_54[5]  ^ frame_54[6]  ^ frame_54[9]  ^ 
                         frame_54[10] ^ frame_54[13] ^ frame_54[14] ^ frame_54[17] ^ frame_54[18] ^ 
                         frame_54[21] ^ frame_54[22] ^ frame_54[25] ^ frame_54[26] ^ frame_54[22] ^ 
                         frame_54[29] ^ frame_54[30] ^ frame_54[33] ^ frame_54[34] ^ frame_54[37] ^ 
                         frame_54[38] ^ frame_54[41] ^ frame_54[42] ^ frame_54[45] ^ frame_54[46] ^ 
                         frame_54[49] ^ frame_54[50] ^ frame_54[53];

    assign syndrome[2] = frame_54[3]  ^ frame_54[4]  ^ frame_54[5]  ^ frame_54[6]  ^ frame_54[11] ^ 
                         frame_54[12] ^ frame_54[13] ^ frame_54[14] ^ frame_54[19] ^ frame_54[20] ^ 
                         frame_54[21] ^ frame_54[22] ^ frame_54[27] ^ frame_54[28] ^ frame_54[29] ^ 
                         frame_54[30] ^ frame_54[35] ^ frame_54[36] ^ frame_54[37] ^ frame_54[38] ^ 
                         frame_54[43] ^ frame_54[44] ^ frame_54[45] ^ frame_54[46] ^ frame_54[51] ^ 
                         frame_54[52] ^ frame_54[53];

    assign syndrome[3] = |frame_54[14:7]  ^ |frame_54[30:23] ^ |frame_54[46:39];
    assign syndrome[4] = |frame_54[30:15] ^ |frame_54[53:47];
    assign syndrome[5] = |frame_54[53:31];

    // Расчет общего четностного бита по всему принятому 54-битному слову
    wire calc_overall_parity = ^frame_54;
    wire parity_error = (calc_overall_parity != received_overall_parity);

    // Массив для хранения исправленного слова перед извлечением данных
    reg [53:0] corrected_frame_54;

    // Логика декодирования SEC-DED
    always @(*) begin
        corrected_frame_54 = frame_54;
        double_error = 1'b0;
        
        if (syndrome == 6'd0) begin
            // Ошибок нет
            double_error = 1'b0;
        end else if (syndrome != 6'd0 && parity_error) begin
            // Одиночная ошибка найдена -> исправляем по индексу синдрома
            if (syndrome <= 6'd54) begin
                corrected_frame_54[syndrome - 1] = ~frame_54[syndrome - 1];
            end
            double_error = 1'b0;
        end else if (syndrome != 6'd0 && !parity_error) begin
            // Синдром не ноль, но общий паритет сошелся -> обнаружена двойная ошибка!
            double_error = 1'b1;
        end
    end

    // Извлечение 48 информационных бит (удаление проверочных позиций: 1, 2, 4, 8, 16, 32)
    // Сопоставление позиций полностью эквивалентно функции setdiff(1:54, parity_pos) из MATLAB
    always @(*) begin
        data_out[0]  = corrected_frame_54[2];  // Позиция 3
        data_out[1]  = corrected_frame_54[4];  // Позиция 5
        data_out[2]  = corrected_frame_54[5];  // Позиция 6
        data_out[3]  = corrected_frame_54[6];  // Позиция 7
        data_out[4]  = corrected_frame_54[8];  // Позиция 9
        data_out[5]  = corrected_frame_54[9];  // Позиция 10
        data_out[6]  = corrected_frame_54[10]; // Позиция 11
        data_out[7]  = corrected_frame_54[11]; // Позиция 12
        data_out[8]  = corrected_frame_54[12]; // Позиция 13
        data_out[9]  = corrected_frame_54[13]; // Позиция 14
        data_out[10] = corrected_frame_54[14]; // Позиция 15
        data_out[11] = corrected_frame_54[16]; // Позиция 17
        data_out[12] = corrected_frame_54[17]; // Позиция 18
        data_out[13] = corrected_frame_54[18]; // Позиция 19
        data_out[14] = corrected_frame_54[19]; // Позиция 20
        data_out[15] = corrected_frame_54[20]; // Позиция 21
        data_out[16] = corrected_frame_54[21]; // Позиция 22
        data_out[17] = corrected_frame_54[22]; // Позиция 23
        data_out[18] = corrected_frame_54[23]; // Позиция 24
        data_out[19] = corrected_frame_54[24]; // Позиция 25
        data_out[20] = corrected_frame_54[25]; // Позиция 26
        data_out[21] = corrected_frame_54[26]; // Позиция 27
        data_out[22] = corrected_frame_54[27]; // Позиция 28
        data_out[23] = corrected_frame_54[28]; // Позиция 29
        data_out[24] = corrected_frame_54[29]; // Позиция 30
        data_out[25] = corrected_frame_54[30]; // Позиция 31
        data_out[26] = corrected_frame_54[32]; // Позиция 33
        data_out[27] = corrected_frame_54[33]; // Позиция 34
        data_out[28] = corrected_frame_54[34]; // Позиция 35
        data_out[29] = corrected_frame_54[35]; // Позиция 36
        data_out[30] = corrected_frame_54[36]; // Позиция 37
        data_out[31] = corrected_frame_54[37]; // Позиция 38
        data_out[32] = corrected_frame_54[38]; // Позиция 39
        data_out[33] = corrected_frame_54[39]; // Позиция 40
        data_out[34] = corrected_frame_54[40]; // Позиция 41
        data_out[35] = corrected_frame_54[41]; // Позиция 42
        data_out[36] = corrected_frame_54[42]; // Позиция 43
        data_out[37] = corrected_frame_54[43]; // Позиция 44
        data_out[38] = corrected_frame_54[44]; // Позиция 45
        data_out[39] = corrected_frame_54[45]; // Позиция 46
        data_out[40] = corrected_frame_54[46]; // Позиция 47
        data_out[41] = corrected_frame_54[47]; // Позиция 48
        data_out[42] = corrected_frame_54[48]; // Позиция 49
        data_out[43] = corrected_frame_54[49]; // Позиция 50
        data_out[44] = corrected_frame_54[50]; // Позиция 51
        data_out[45] = corrected_frame_54[51]; // Позиция 52
        data_out[46] = corrected_frame_54[52]; // Позиция 53
        data_out[47] = corrected_frame_54[53]; // Позиция 54
    end

endmodule
