function [code_word, hamming_word] = ecc_hamming_encode(data_bits, config)
% ECC_HAMMING_ENCODE  Extended Hamming SEC-DED for 48 data + 6 parity + overall.

    if nargin < 2 || isempty(config)
        parity_pos = [1, 2, 4, 8, 16, 32];
        code_length = 54;
        info_pos = setdiff(1:code_length, parity_pos);
    else
        parity_pos = config.hamming.parity_pos;
        code_length = config.hamming.code_length;
        info_pos = config.hamming.info_pos;
    end
    assert(numel(data_bits) == numel(info_pos), 'Expected 48 data bits');

    hamming_word = zeros(1, code_length);
    hamming_word(info_pos) = double(data_bits(:)');
    for parity_index = 1:numel(parity_pos)
        parity_position = parity_pos(parity_index);
        covered = bitget(1:code_length, log2(parity_position) + 1) ~= 0;
        covered(parity_position) = false;
        hamming_word(parity_position) = mod(sum(hamming_word(covered)), 2);
    end
    overall_parity = mod(sum(hamming_word), 2);
    code_word = [hamming_word, overall_parity];
end
