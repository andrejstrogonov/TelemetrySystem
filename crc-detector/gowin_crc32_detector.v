//==========================================================================
// ОПТИМИЗИРОВАННЫЙ RTL-МОДУЛЬ ДЕТЕКТОРА CRC-32/MPEG-2 ДЛЯ GOWIN
//==========================================================================

module custom_crc32_detector (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        dataIn,   // 1 бит последовательного потока телеметрии
    input  wire        startIn,  // Маркер первого бита кадра
    input  wire        endIn,    // Маркер последнего бита кадра
    input  wire        validIn,  // Строб валидности данных
    output reg         err       // Флаг ошибки (1 = сбой контрольной суммы)
);

    // Стандартный полином CRC-32/MPEG-2
    localparam [31:0] POLY = 32'h04C11DB7;
    
    reg [31:0] crc_reg;
    wire       crc_msb;
    wire       data_bit;
    
    assign data_bit = dataIn; 
    assign crc_msb  = crc_reg[31]; // Проверяем самый старший (31-й) бит регистра CRC

    // Основной автомат расчета CRC-32
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_reg <= 32'hFFFFFFFF; // Стандартная инициализация MPEG-2
            err     <= 1'b0;
        end else if (validIn) begin
            
            if (startIn) begin
                // Инициализация первого такта (эквивалент сдвига константы 32'hFFFFFFFF)
                if (1'b1 ^ data_bit)
                    crc_reg <= 32'hFFFFFFFE ^ POLY;
                else
                    crc_reg <= 32'hFFFFFFFE;
            end else begin
                // Побитовый сдвиг кадра в процессе передачи тела пакета
                if (crc_msb ^ data_bit)
                    crc_reg <= {crc_reg[30:0], 1'b0} ^ POLY;
                else
                    crc_reg <= {crc_reg[30:0], 1'b0};
            end
            
            // Фиксация результата строго по маркеру endIn (на 55-м бите кадра)
            if (endIn) begin
                if (crc_reg == 32'h00000000)
                    err <= 1'b0; // CRC OK
                else
                    err <= 1'b1; // CRC FAILED
            end
        end else begin
            err <= 1'b0;
        end
    end

endmodule

