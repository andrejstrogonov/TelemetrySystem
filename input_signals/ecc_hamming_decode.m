function [data_out, status, syndrome, corrected_word] = ecc_hamming_decode(code_word, config)
% ECC_HAMMING_DECODE  Extended Hamming SEC-DED for a 55-bit code word.

    if nargin < 2 || isempty(config)
        parity_pos = [1, 2, 4, 8, 16, 32];
        code_length = 54;
        info_pos = setdiff(1:code_length, parity_pos);
    else
        parity_pos = config.hamming.parity_pos;
        code_length = config.hamming.code_length;
        info_pos = config.hamming.info_pos;
    end
    assert(numel(code_word) == code_length + 1, 'Expected 55-bit code word');

    corrected_word = double(code_word(:)');
    hamming_word = corrected_word(1:code_length);
    received_overall = corrected_word(end);
    syndrome = 0;
    for parity_index = 1:numel(parity_pos)
        parity_position = parity_pos(parity_index);
        covered = bitget(1:code_length, log2(parity_position) + 1) ~= 0;
        if mod(sum(hamming_word(covered)), 2) ~= 0
            syndrome = syndrome + parity_position;
        end
    end
    overall_mismatch = mod(sum(hamming_word) + received_overall, 2) ~= 0;

    if syndrome == 0 && ~overall_mismatch
        status = 'no_error';
    elseif syndrome == 0 && overall_mismatch
        corrected_word(end) = 1 - corrected_word(end);
        status = 'corrected';
    elseif syndrome ~= 0 && overall_mismatch && syndrome <= code_length
        corrected_word(syndrome) = 1 - corrected_word(syndrome);
        status = 'corrected';
    else
        status = 'uncorrectable';
    end
    data_out = corrected_word(info_pos);
end
