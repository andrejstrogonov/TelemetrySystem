module mcu_arbiter (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        mcu1_heartbeat,
    input  wire        anomaly_detected,
    output reg         mcu1_power_en,
    output reg         mcu1_reset_n,
    output reg         mcu2_power_en,
    output reg         mcu2_reset_n,
    output wire        mcu1_dead
);

    // Константы состояний автомата (One-Hot кодирование)
    localparam ARB_MCU1_ACTIVE = 3'b001;
    localparam ARB_SWITCHING   = 3'b010;
    localparam ARB_MCU2_ACTIVE = 3'b100;
    
    // Параметры временных интервалов
    localparam HEARTBEAT_TIMEOUT  = 24'd10_000_000;
    localparam SWITCH_SETTLE_TIME = 24'd5_000_000;

    // Атрибут для автоматической оптимизации FSM в Vivado и Gowin
    (* fsm_encoding = "one_hot" *) reg [2:0] arbiter_state;
    reg [23:0] hb_timeout_cnt;

    // Комбинаторное определение потери пульса основного процессора
    assign mcu1_dead = (hb_timeout_cnt >= HEARTBEAT_TIMEOUT);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arbiter_state  <= ARB_MCU1_ACTIVE;
            hb_timeout_cnt <= 24'd0;
            mcu1_power_en  <= 1'b1;
            mcu1_reset_n   <= 1'b1;
            mcu2_power_en  <= 1'b0;
            mcu2_reset_n   <= 1'b0;
        end else begin
            case (arbiter_state)
                
                // Состояние 1: Работает основной процессор MCU1
                ARB_MCU1_ACTIVE: begin
                    if (mcu1_heartbeat) begin
                        hb_timeout_cnt <= 24'd0;
                    end else if (!mcu1_dead) begin
                        hb_timeout_cnt <= hb_timeout_cnt + 1'b1;
                    end

                    // Переход на резерв при аварии или таймауте
                    if (mcu1_dead || anomaly_detected) begin
                        mcu1_reset_n   <= 1'b0;  // Сбрасываем MCU1
                        mcu2_power_en  <= 1'b1;  // Включаем питание MCU2
                        hb_timeout_cnt <= 24'd0; // Очищаем счетчик для следующей фазы
                        arbiter_state  <= ARB_SWITCHING;
                    end
                end

                // Состояние 2: Интервал безопасного переключения питания
                ARB_SWITCHING: begin
                    hb_timeout_cnt <= hb_timeout_cnt + 1'b1;
                    mcu2_reset_n   <= 1'b1; // Удерживаем линии сброса активными для MCU2

                    // Ожидание стабилизации переходных процессов питания
                    if (hb_timeout_cnt >= SWITCH_SETTLE_TIME) begin
                        mcu1_power_en <= 1'b0; // Полностью изолируем и обесточиваем MCU1
                        arbiter_state <= ARB_MCU2_ACTIVE;
                    end
                end

                // Состояние 3: Активен резервный процессор MCU2
                ARB_MCU2_ACTIVE: begin
                    mcu2_power_en <= 1'b1;
                    mcu2_reset_n  <= 1'b1;
                    // Логика зафиксирована на работу с MCU2 до системного сброса (rst_n)
                end

                default: begin
                    arbiter_state <= ARB_MCU1_ACTIVE;
                end
            endcase
        end
    end

endmodule
