module ecc_ring_buffer #(
    parameter DEPTH_WIDTH = 9,
    parameter BUFFER_SIZE = (1 << DEPTH_WIDTH)
) (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire [47:0]            data_in,
    input  wire                   data_valid,
    input  wire                   read_en,
    input  wire [DEPTH_WIDTH-1:0] read_addr,
    output wire [47:0]            data_out,
    output reg                    data_out_valid,
    output wire                   single_error_corrected,
    output wire                   double_error_detected
);

    reg [DEPTH_WIDTH-1:0] write_ptr;
    reg [54:0] ram_matrix [0:BUFFER_SIZE-1];
    reg [BUFFER_SIZE-1:0] valid_entries;
    reg [54:0] word_to_decode;
    reg [54:0] corrected_word;
    reg [5:0] syndrome;
    reg overall_mismatch;
    reg [47:0] decoded_data;
    reg uncorrectable;
    integer position;
    integer data_index;
    integer parity_index;

    function [54:0] encode_secded;
        input [47:0] data;
        integer code_position;
        integer input_index;
        integer parity_bit;
        reg [54:0] codeword;
        reg parity_value;
        begin
            codeword = 55'd0;
            input_index = 0;
            for (code_position = 1; code_position <= 54; code_position = code_position + 1) begin
                if ((code_position & (code_position - 1)) != 0) begin
                    codeword[code_position - 1] = data[input_index];
                    input_index = input_index + 1;
                end
            end

            for (parity_bit = 0; parity_bit < 6; parity_bit = parity_bit + 1) begin
                parity_value = 1'b0;
                for (code_position = 1; code_position <= 54; code_position = code_position + 1) begin
                    if ((code_position & (1 << parity_bit)) != 0) begin
                        parity_value = parity_value ^ codeword[code_position - 1];
                    end
                end
                codeword[(1 << parity_bit) - 1] = parity_value;
            end
            codeword[54] = ^codeword[53:0];
            encode_secded = codeword;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr <= {DEPTH_WIDTH{1'b0}};
            valid_entries <= {BUFFER_SIZE{1'b0}};
            word_to_decode <= 55'd0;
            data_out_valid <= 1'b0;
        end else begin
            if (data_valid) begin
                ram_matrix[write_ptr] <= encode_secded(data_in);
                valid_entries[write_ptr] <= 1'b1;
                write_ptr <= write_ptr + 1'b1;
            end

            if (read_en) begin
                if (valid_entries[read_addr]) begin
                    word_to_decode <= ram_matrix[read_addr];
                    data_out_valid <= 1'b1;
                end else begin
                    word_to_decode <= 55'd0;
                    data_out_valid <= 1'b0;
                end
            end else begin
                data_out_valid <= 1'b0;
            end
        end
    end

    always @(*) begin
        syndrome = 6'd0;
        for (parity_index = 0; parity_index < 6; parity_index = parity_index + 1) begin
            for (position = 1; position <= 54; position = position + 1) begin
                if ((position & (1 << parity_index)) != 0) begin
                    syndrome[parity_index] = syndrome[parity_index] ^ word_to_decode[position - 1];
                end
            end
        end
        overall_mismatch = ^word_to_decode;
        corrected_word = word_to_decode;
        uncorrectable = 1'b0;

        if (syndrome != 6'd0 && overall_mismatch) begin
            if (syndrome <= 6'd54) begin
                corrected_word[syndrome - 1'b1] = ~word_to_decode[syndrome - 1'b1];
            end else begin
                uncorrectable = 1'b1;
            end
        end else if (syndrome != 6'd0 && !overall_mismatch) begin
            uncorrectable = 1'b1;
        end

        decoded_data = 48'd0;
        data_index = 0;
        for (position = 1; position <= 54; position = position + 1) begin
            if ((position & (position - 1)) != 0) begin
                decoded_data[data_index] = corrected_word[position - 1];
                data_index = data_index + 1;
            end
        end
        if (uncorrectable) begin
            decoded_data = 48'd0;
        end
    end

    assign data_out = decoded_data;
    assign single_error_corrected = data_out_valid && overall_mismatch && !uncorrectable;
    assign double_error_detected = data_out_valid && uncorrectable;

endmodule