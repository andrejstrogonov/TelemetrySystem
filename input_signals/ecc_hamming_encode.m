function [frame, hamming_code] = ecc_hamming_encode(data_bits, config)
% ECC_HAMMING_ENCODE  Кодирование 24 бит данных расширенным кодом
%                       Хэмминга SEC-DED (31,26) + overall parity.
%
%   frame = ecc_hamming_encode(data_bits)
%   frame = ecc_hamming_encode(data_bits, config)
%
%   Вход:
%     data_bits  — вектор 24 бит (0/1): payload(16) + CRC(8)
%     config     — структура конфигурации (опционально)
%
%   Выход:
%     frame       — вектор 32 бит (0/1):
%                   [1:24] данные, [25:29] Hamming parity,
%                   [30] overall parity, [31:32] резерв (0)
%     hamming_code — полный 31-битный код Хэмминга (для отладки)

    if nargin < 2 || isempty(config)
        parity_pos = [1, 2, 4, 8, 16];
        info_pos   = [3, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15, ...
                     17, 18, 19, 20, 21, 22, 23, 24, 25, 26, ...
                     27, 28, 29, 30, 31];
        used_info  = 24;
        code_len   = 31;
    else
        parity_pos = config.hamming.parity_pos;
        info_pos   = config.hamming.info_pos;
        used_info  = config.hamming.used_info;
        code_len   = config.hamming.code_length;
    end

    n_parity = numel(parity_pos);   % 5
    n_info   = numel(info_pos);     % 26

    assert(numel(data_bits) <= used_info, ...
        'data_bits (%d) превышает used_info (%d)', ...
        numel(data_bits), used_info);

    % Заполняем инфо-позиции: 24 данных + 2 заглушки (нули)
    info_values = [data_bits(:)', zeros(1, n_info - used_info)];

    % Строим 31-битный код Хэмминга
    hamming_code = zeros(1, code_len);

    % Размещаем инфо-биты
    hamming_code(info_pos) = info_values;

    % Вычисляем каждый проверочный бит
    for p = 1:n_parity
        pp = parity_pos(p);
        % Маска: все позиции, где бит pp установлен в индексе
        % (включая саму parity-позицию — она и есть результат)
        mask = false(1, code_len);
        for i = 1:code_len
            if i ~= pp && bitand(i, uint16(pp)) ~= 0
                mask(i) = true;
            end
        end
        hamming_code(pp) = mod(sum(hamming_code(mask)), 2);
    end

    % Overall parity (SEC-DED): XOR всех 31 бит
    overall_parity = mod(sum(hamming_code), 2);

    % Формируем 32-битный кадр
    frame = [data_bits(:)', ...
             hamming_code(parity_pos), ...
             overall_parity, ...
             0, 0];

    if nargout > 1
        hamming_code = hamming_code;
    end
end
