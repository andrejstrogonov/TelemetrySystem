function [crc_bits, crc_byte] = crc8_compute(data_bits, polynomial, init_val, xor_out)
% CRC8_COMPUTE  Вычисление CRC-8 для битового вектора.
%
%   [crc_bits, crc_byte] = crc8_compute(data_bits)
%   [crc_bits, crc_byte] = crc8_compute(data_bits, polynomial, init_val, xor_out)
%
%   Вход:
%     data_bits   — вектор бит (0/1), последовательность для проверки
%     polynomial  — полином CRC-8 (hex), по умолчанию 0x07 (ATM)
%     init_val    — начальное значение (hex), по умолч 0xFF
%     xor_out     — финальный XOR (hex), по умолчанию 0x00
%
%   Выход:
%     crc_bits    — вектор 8 бит (0/1), MSB first
%     crc_byte    — целое число 0..255

    if nargin < 2 || isempty(polynomial), polynomial = 0x07; end
    if nargin < 3 || isempty(init_val),    init_val    = 0xFF; end
    if nargin < 4 || isempty(xor_out),     xor_out     = 0x00; end

    crc = uint8(init_val);
    poly = uint8(polynomial);

    for i = 1:numel(data_bits)
        bit_in = data_bits(i);

        % Проверяем старший бит регистра
        msb = bitand(crc, uint8(128)) ~= 0;

        % Сдвиг влево на 1
        crc = bitshift(crc, 1, 'uint8');

        % Если XOR(msb, bit_in) = 1 → XOR с полиномом
        if xor(logical(msb), logical(bit_in))
            crc = bitxor(crc, poly);
        end
    end

    % Финальный XOR
    crc = bitxor(crc, uint8(xor_out));

    % Преобразование в битовый вектор (MSB first)
    crc_bits = zeros(1, 8);
    crc_byte = double(crc);
    for b = 1:8
        crc_bits(b) = bitand(bitshift(crc, -(8 - b)), 1);
    end
end
