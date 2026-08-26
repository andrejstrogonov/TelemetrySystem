function [data_out, ecc_corrected, ecc_uncorrectable] = fcn(r)
    % r: принятое из памяти 39-битное слово
    
    % Инициализация флагов
    ecc_corrected = 0;
    ecc_uncorrectable = 0;
    
    % 1. Вычисляем синдром Хэмминга (6 бит)
    s = zeros(1, 6);
    s(1) = mod(sum(r([1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31, 33, 35, 37])), 2);
    s(2) = mod(sum(r([2, 3, 6, 7, 10, 11, 14, 15, 18, 19, 22, 23, 26, 27, 30, 31, 34, 35, 38])), 2);
    s(3) = mod(sum(r([4, 5, 6, 7, 12, 13, 14, 15, 20, 21, 22, 23, 28, 29, 30, 31, 36, 37, 38])), 2);
    s(4) = mod(sum(r([8:15, 24:31, 38])), 2);
    s(5) = mod(sum(r([16:31])), 2);
    s(6) = mod(sum(r([32:38])), 2);
    
    % Преобразуем синдром в десятичное число (индекс ошибочного бита)
    syndrome_val = s(1)*1 + s(2)*2 + s(3)*4 + s(4)*8 + s(5)*16 + s(6)*32;
    
    % 2. Вычисляем общий паритет принятого слова
    overall_parity = mod(sum(r), 2); % Если ошибок нет, общий паритет должен быть равен 0
    
    % 3. Логика SECDED декодирования
    if syndrome_val == 0
        if overall_parity == 0
            % Ошибок нет
        else
            % Ошибка в самом бите общего паритета (39)
            r(39) = mod(r(39) + 1, 2);
            ecc_corrected = 1;
        end
    else
        if overall_parity == 1
            % Одиночная ошибка (SEC) — исправляем её
            if syndrome_val <= 39
                r(syndrome_val) = mod(r(syndrome_val) + 1, 2);
                ecc_corrected = 1;
            end
        else
            % Двойная ошибка (DED) — обнаружена, но неисправима
            ecc_uncorrectable = 1;
        end
    end
    
    % Извлекаем чистые 32 бита данных из исправленного слова
    data_pos =;
    data_out = zeros(1, 32);
    for i = 1:32
        data_out(i) = r(data_pos(i));
    end
end
