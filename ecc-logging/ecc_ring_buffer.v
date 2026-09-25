// Активируйте макрос ниже, ТОЛЬКО если вы хотите использовать сгенерированный netlist из .vg файла.
// По умолчанию макрос закомментирован, чтобы использовался этот чистый поведенческий код.
// `define USE_GEN_NETLIST

`ifndef USE_GEN_NETLIST

module ecc_ring_buffer #(
    parameter DEPTH_WIDTH = 8,
    parameter BUFFER_SIZE = (1 << DEPTH_WIDTH)
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [31:0] data_in,
    input  wire        data_valid,

    output reg  [31:0] data_out,
    output reg         single_error_corrected,
    output reg         double_error_detected
);

    reg [DEPTH_WIDTH-1:0] write_ptr;
    reg [DEPTH_WIDTH-1:0] read_ptr;

    reg [38:0] ram_matrix [0:BUFFER_SIZE-1];

    wire [6:0] ecc_generated;
    wire [38:0] word_to_write;

    reg  [38:0] word_to_decode;
    wire [6:0] syndrome;
    reg  [31:0] corrected_data;

    // Генерация контрольных сумм ECC (оптимально для любого синтезатора: Vivado / Gowin)
    assign ecc_generated[0] = data_in[0]^data_in[1]^data_in[3]^data_in[4]^data_in[6]^data_in[8]^data_in[10]^data_in[11]^data_in[13]^data_in[15]^data_in[17]^data_in[19]^data_in[21]^data_in[23]^data_in[25]^data_in[26]^data_in[28]^data_in[30];
    assign ecc_generated[1] = data_in[0]^data_in[2]^data_in[3]^data_in[5]^data_in[6]^data_in[9]^data_in[10]^data_in[12]^data_in[13]^data_in[16]^data_in[17]^data_in[20]^data_in[21]^data_in[24]^data_in[25]^data_in[27]^data_in[28]^data_in[31];
    assign ecc_generated[2] = data_in[1]^data_in[2]^data_in[3]^data_in[7]^data_in[8]^data_in[9]^data_in[10]^data_in[14]^data_in[15]^data_in[16]^data_in[17]^data_in[22]^data_in[23]^data_in[24]^data_in[25]^data_in[29]^data_in[30]^data_in[31];
    assign ecc_generated[3] = data_in[4]^data_in[5]^data_in[6]^data_in[7]^data_in[8]^data_in[9]^data_in[10]^data_in[18]^data_in[19]^data_in[20]^data_in[21]^data_in[22]^data_in[23]^data_in[24]^data_in[25];
    assign ecc_generated[4] = data_in[11]^data_in[12]^data_in[13]^data_in[14]^data_in[15]^data_in[16]^data_in[17]^data_in[18]^data_in[19]^data_in[20]^data_in[21]^data_in[22]^data_in[23]^data_in[24]^data_in[25];
    assign ecc_generated[5] = data_in[26]^data_in[27]^data_in[28]^data_in[29]^data_in[30]^data_in[31];
    assign ecc_generated[6] = (^data_in) ^ (^ecc_generated[5:0]);

    assign word_to_write = {ecc_generated[6], data_in, ecc_generated[5:0]};

    // Буфер памяти
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr <= 0;
            read_ptr  <= 0;
        end else begin
            if (data_valid) begin
                ram_matrix[write_ptr] <= word_to_write;
                write_ptr <= write_ptr + 1'b1;

                if (write_ptr == read_ptr) begin
                    read_ptr <= read_ptr + 1'b1;
                end
            end
        end
    end

    always @(posedge clk) begin
        word_to_decode <= ram_matrix[read_ptr];
    end

    // Вычисление синдрома ошибок
    assign syndrome[0] = word_to_decode[0] ^ word_to_decode[2] ^ word_to_decode[4] ^ word_to_decode[6] ^ word_to_decode[8] ^ word_to_decode[10] ^ word_to_decode[12] ^ word_to_decode[14] ^ word_to_decode[16] ^ word_to_decode[18] ^ word_to_decode[20] ^ word_to_decode[22] ^ word_to_decode[24] ^ word_to_decode[26] ^ word_to_decode[28] ^ word_to_decode[30] ^ word_to_decode[32] ^ word_to_decode[34] ^ word_to_decode[36] ^ word_to_decode[38];
    assign syndrome[1] = word_to_decode[1] ^ word_to_decode[2] ^ word_to_decode[5] ^ word_to_decode[6] ^ word_to_decode[9] ^ word_to_decode[10] ^ word_to_decode[13] ^ word_to_decode[14] ^ word_to_decode[17] ^ word_to_decode[18] ^ word_to_decode[21] ^ word_to_decode[22] ^ word_to_decode[25] ^ word_to_decode[26] ^ word_to_decode[29] ^ word_to_decode[30] ^ word_to_decode[33] ^ word_to_decode[34] ^ word_to_decode[37] ^ word_to_decode[38];
    assign syndrome[2] = word_to_decode[3] ^ word_to_decode[4] ^ word_to_decode[5] ^ word_to_decode[6] ^ word_to_decode[11] ^ word_to_decode[12] ^ word_to_decode[13] ^ word_to_decode[14] ^ word_to_decode[19] ^ word_to_decode[20] ^ word_to_decode[21] ^ word_to_decode[22] ^ word_to_decode[27] ^ word_to_decode[28] ^ word_to_decode[29] ^ word_to_decode[30] ^ word_to_decode[35] ^ word_to_decode[36] ^ word_to_decode[37] ^ word_to_decode[38];
    assign syndrome[3] = word_to_decode[7] ^ word_to_decode[8] ^ word_to_decode[9] ^ word_to_decode[10] ^ word_to_decode[11] ^ word_to_decode[12] ^ word_to_decode[13] ^ word_to_decode[14] ^ word_to_decode[23] ^ word_to_decode[24] ^ word_to_decode[25] ^ word_to_decode[26] ^ word_to_decode[27] ^ word_to_decode[28] ^ word_to_decode[29] ^ word_to_decode[30];
    assign syndrome[4] = word_to_decode[15] ^ word_to_decode[16] ^ word_to_decode[17] ^ word_to_decode[18] ^ word_to_decode[19] ^ word_to_decode[20] ^ word_to_decode[21] ^ word_to_decode[22] ^ word_to_decode[23] ^ word_to_decode[24] ^ word_to_decode[25] ^ word_to_decode[26] ^ word_to_decode[27] ^ word_to_decode[28] ^ word_to_decode[29] ^ word_to_decode[30];
    assign syndrome[5] = word_to_decode[31] ^ word_to_decode[32] ^ word_to_decode[33] ^ word_to_decode[34] ^ word_to_decode[35] ^ word_to_decode[36] ^ word_to_decode[37] ^ word_to_decode[38];
    assign syndrome[6] = ^word_to_decode;

    // Исправление одиночных ошибок (SECDED)
     always @(*) begin
        corrected_data = word_to_decode[37:6];

        if (syndrome[5:0] != 6'b000000) begin
            if (syndrome[6] == 1'b1) begin
                case (syndrome[5:0])
                    6'd3:  corrected_data[0]  = !word_to_decode[6];
                    6'd5:  corrected_data[1]  = !word_to_decode[7];
                    6'd6:  corrected_data[2]  = !word_to_decode[8];
                    6'd7:  corrected_data[3]  = !word_to_decode[9];
                    6'd9:  corrected_data[4]  = !word_to_decode[10];
                    6'd10: corrected_data[5]  = !word_to_decode[11];
                    6'd11: corrected_data[6]  = !word_to_decode[12];
                    6'd12: corrected_data[7]  = !word_to_decode[13];
                    6'd13: corrected_data[8]  = !word_to_decode[14];
                    6'd14: corrected_data[9]  = !word_to_decode[15];
                    6'd15: corrected_data[10] = !word_to_decode[16];
                    6'd17: corrected_data[11] = !word_to_decode[17];
                    6'd18: corrected_data[12] = !word_to_decode[18];
                    6'd19: corrected_data[13] = !word_to_decode[19];
                    6'd20: corrected_data[14] = !word_to_decode[20];
                    6'd21: corrected_data[15] = !word_to_decode[21];
                    6'd22: corrected_data[16] = !word_to_decode[22];
                    6'd23: corrected_data[17] = !word_to_decode[23];
                    6'd24: corrected_data[18] = !word_to_decode[24];
                    6'd25: corrected_data[19] = !word_to_decode[25];
                    6'd26: corrected_data[20] = !word_to_decode[26];
                    6'd27: corrected_data[21] = !word_to_decode[27];
                    6'd28: corrected_data[22] = !word_to_decode[28];
                    6'd29: corrected_data[23] = !word_to_decode[29];
                    6'd30: corrected_data[24] = !word_to_decode[30];
                    6'd31: corrected_data[25] = !word_to_decode[31];
                    6'd33: corrected_data[26] = !word_to_decode[32];
                    6'd34: corrected_data[27] = !word_to_decode[33];
                    6'd35: corrected_data[28] = !word_to_decode[34];
                    6'd36: corrected_data[29] = !word_to_decode[35];
                    6'd37: corrected_data[30] = !word_to_decode[36];
                    6'd38: corrected_data[31] = !word_to_decode[37];
                    default: corrected_data = word_to_decode[37:6];
                endcase
            end
        end
    end

    // Выходной регистр и диагностические флаги
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out               <= 32'd0;
            single_error_corrected <= 1'b0;
            double_error_detected  <= 1'b0;
        end else begin
            data_out <= corrected_data;

            if (syndrome[5:0] != 6'b000000) begin
                if (syndrome[6] == 1'b1) begin
                    single_error_corrected <= 1'b1;
                    double_error_detected  <= 1'b0;
                end else begin
                    single_error_corrected <= 1'b0;
                    double_error_detected  <= 1'b1;
                end
            end else begin
                single_error_corrected <= 1'b0;
                double_error_detected  <= 1'b0;
            end
        end
    end
endmodule

`endif
