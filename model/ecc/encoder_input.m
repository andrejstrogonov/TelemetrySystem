function code_word = encoder_input(data_in)
% ENCODER_INPUT  Rev A extended Hamming encoder: 48 data -> 55 bits.
    assert(numel(data_in) == 48, 'Expected 48 data bits');
    parity_pos = [1, 2, 4, 8, 16, 32];
    data_pos = setdiff(1:54, parity_pos);
    code_word = zeros(1, 55);
    code_word(data_pos) = data_in(:)';
    for index = 1:numel(parity_pos)
        position = parity_pos(index);
        covered = bitget(1:54, log2(position) + 1) ~= 0;
        covered(position) = false;
        code_word(position) = mod(sum(code_word(covered)), 2);
    end
    code_word(55) = mod(sum(code_word(1:54)), 2);
end
