function [data_out, ecc_corrected, ecc_uncorrectable] = turbo_decoder(r)
% TURBO_DECODER  Rev A extended Hamming decoder: 55 bits -> 48 data bits.
    assert(numel(r) == 55, 'Expected 55-bit code word');
    parity_pos = [1, 2, 4, 8, 16, 32];
    data_pos = setdiff(1:54, parity_pos);
    syndrome = 0;
    for index = 1:numel(parity_pos)
        position = parity_pos(index);
        covered = bitget(1:54, log2(position) + 1) ~= 0;
        if mod(sum(r(covered)), 2) ~= 0
            syndrome = syndrome + position;
        end
    end
    overall_error = mod(sum(r), 2) ~= 0;
    ecc_corrected = 0;
    ecc_uncorrectable = 0;
    if syndrome == 0 && overall_error
        r(55) = 1 - r(55);
        ecc_corrected = 1;
    elseif syndrome ~= 0 && overall_error && syndrome <= 54
        r(syndrome) = 1 - r(syndrome);
        ecc_corrected = 1;
    elseif syndrome ~= 0 && ~overall_error
        ecc_uncorrectable = 1;
    end
    data_out = r(data_pos);
end
