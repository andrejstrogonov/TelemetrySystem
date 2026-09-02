function [data_out, status, syndrome, corrected_frame] = ecc_hamming_decode(frame, config)
% ECC_HAMMING_DECODE  Декодирование 32-битного кадра, коррекция
%                       одиночных ошибок (SEC), обнаружение двойных (DED).
%
%   [data_out, status]                    = ecc_hamming_decode(frame)
%   [data_out, status, syndrome]          = ecc_hamming_decode(frame)
%   [data_out, status, syndrome, corrected_frame] = ecc_hamming_decode(frame, config)
%
%   Вход:
%     frame   — вектор 32 бита (0/1)
%     config  — структура конфигурации (опционально)
%
%   Выход:
%     data_out        — вектор 24 бита (0/1): восстановленные данные
%     status          — 'no_error' | 'corrected' | 'uncorrectable'
%     syndrome        — целое число (0 = ошибок нет)
%     corrected_frame — 32-битный кадр после коррекции (для отладки)

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

    % Извлекаем компоненты из кадра
    data_bits    = frame(1:24)';
    hamming_par  = frame(25:29)';
    overall_par  = frame(30);

    % Восстанавливаем 31-битный код Хэмминга
    hamming_code = zeros(1, code_len);
    hamming_code(info_pos) = [data_bits, zeros(1, numel(info_pos) - used_info)];
    hamming_code(parity_pos) = hamming_par;

    % ── Вычисление синдрома ──
    syndrome = 0;
    for p = 1:numel(parity_pos)
        pp = parity_pos(p);
        mask = false(1, code_len);
        for i = 1:code_len
            if bitand(uint16(i), uint16(pp)) ~= 0
                mask(i) = true;
            end
        end
        s = mod(sum(hamming_code(mask)), 2);
        syndrome = syndrome + s * (2^(p-1));
    end

    % ── Проверка общего паритета ──
    computed_overall = mod(sum(hamming_code), 2);
    parity_mismatch  = (overall_par ~= computed_overall);

    % ── Логика SEC-DED ──
    corrected_frame = frame(:)';

    if syndrome == 0
        if ~parity_mismatch
            % Ошибок нет
            status = 'no_error';
        else
            % Ошибка в бите общего паритета → исправляем
            corrected_frame(30) = 1 - corrected_frame(30);
            status = 'corrected';
        end
    else
        if parity_mismatch
            % Одиночная ошибка в данных или Hamming parity → исправляем
            if syndrome <= code_len
                % Коррекция в 31-битном коде
                hamming_code_corrected = hamming_code;
                hamming_code_corrected(syndrome) = 1 - hamming_code_corrected(syndrome);

                % Обновляем data_bits из исправленного кода
                corrected_info = hamming_code_corrected(info_pos);
                data_bits = corrected_info(1:used_info);

                % Обновляем corrected_frame
                corrected_frame(1:24) = data_bits;
                corrected_frame(25:29) = hamming_code_corrected(parity_pos);
                corrected_frame(30) = 1 - corrected_frame(30);  % фиксим overall
            end
            status = 'corrected';
        else
            % Двойная (или более) ошибка — не исправимо
            status = 'uncorrectable';
        end
    end

    data_out = data_bits(:)';
end
