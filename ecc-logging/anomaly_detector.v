module anomaly_detector (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] ecc_data_buffered,
    output wire        anomaly_detected
);

    // Константы состояний автомата
    localparam STATE_OK      = 2'b00;
    localparam STATE_WARNING = 2'b01; // Зарезервировано
    localparam STATE_CRASH   = 2'b10;

    // Три независимых регистра для реализации TMR
    reg [1:0] fsm_state_1, fsm_state_2, fsm_state_3;
    
    // Мажоритарный выбор состояния (побитовое голосование 2-битных векторов)
    wire [1:0] voted_state;
    assign voted_state[0] = (fsm_state_1[0] & fsm_state_2[0]) | 
                            (fsm_state_2[0] & fsm_state_3[0]) | 
                            (fsm_state_1[0] & fsm_state_3[0]);
                            
    assign voted_state[1] = (fsm_state_1[1] & fsm_state_2[1]) | 
                            (fsm_state_2[1] & fsm_state_3[1]) | 
                            (fsm_state_1[1] & fsm_state_3[1]);

    // Выходной сигнал аварии
    assign anomaly_detected = (voted_state == STATE_CRASH);

    // Логика переходов автоматов (использует безопасное мажоритарное состояние)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fsm_state_1 <= STATE_OK;
            fsm_state_2 <= STATE_OK;
            fsm_state_3 <= STATE_OK;
        end else begin
            case (voted_state)
                STATE_OK: begin
                    if (ecc_data_buffered > 32'hFFFF0000) begin
                        fsm_state_1 <= STATE_CRASH;
                        fsm_state_2 <= STATE_CRASH;
                        fsm_state_3 <= STATE_CRASH;
                    end
                end
                
                STATE_CRASH: begin
                    if (ecc_data_buffered < 32'h0000FFFF) begin
                        fsm_state_1 <= STATE_OK;
                        fsm_state_2 <= STATE_OK;
                        fsm_state_3 <= STATE_OK;
                    end
                end
                
                default: begin
                    // Самовосстановление: если один автомат сбойнул (например, STATE_WARNING),
                    // мажоритарная логика вернет все три копии к STATE_OK.
                    fsm_state_1 <= STATE_OK;
                    fsm_state_2 <= STATE_OK;
                    fsm_state_3 <= STATE_OK;
                end
            endcase
        end
    end

endmodule
