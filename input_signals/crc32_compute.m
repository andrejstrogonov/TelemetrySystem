function [crc_bits, crc_word] = crc32_compute(data_bits, polynomial, init_val, xor_out)
% CRC32_COMPUTE  CRC-32/MPEG-2, MSB first, no bit reflection.

    if nargin < 2 || isempty(polynomial), polynomial = uint32(hex2dec('04C11DB7')); end
    if nargin < 3 || isempty(init_val), init_val = uint32(hex2dec('FFFFFFFF')); end
    if nargin < 4 || isempty(xor_out), xor_out = uint32(0); end

    crc = uint32(init_val);
    polynomial = uint32(polynomial);
    for index = 1:numel(data_bits)
        top_bit = bitget(crc, 32) ~= 0;
        crc = bitshift(crc, 1);
        if xor(top_bit, logical(data_bits(index)))
            crc = bitxor(crc, polynomial);
        end
    end
    crc = bitxor(crc, uint32(xor_out));
    crc_word = crc;
    crc_bits = zeros(1, 32);
    for bit_index = 1:32
        crc_bits(bit_index) = bitget(crc, 33 - bit_index);
    end
end