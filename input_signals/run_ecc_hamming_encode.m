%% RUN_ECC_HAMMING_ENCODE
% Самостоятельная инициализация данных, кодирование и декодирование.
% Запустите этот скрипт кнопкой Run вместо файлов функций.

script_dir = fileparts(mfilename('fullpath'));
addpath(script_dir);

% Загрузить конфигурацию без зависимости от текущей папки MATLAB.
run(fullfile(script_dir, 'owon_hds242s_config.m'));

% Создать воспроизводимый payload, вычислить CRC и собрать 48 бит данных.
rng(config.test.payload_seed, 'twister');
payload = randi([0 1], 1, config.frame.payload_bits);
[crc_bits, ~] = crc32_compute(payload, ...
    config.crc.polynomial, config.crc.init, config.crc.xor_out);
data_bits = [payload, crc_bits];

% Закодировать 48 бит в 55-битный extended Hamming SEC-DED кадр.
[code_word, hamming_word] = ecc_hamming_encode(data_bits, config);
[decoded_bits, decode_status, syndrome, corrected_word] = ...
    ecc_hamming_decode(code_word, config);

% Опубликовать результаты в Base Workspace для Simulink и MATLAB.
assignin('base', 'payload', payload);
assignin('base', 'crc_bits', crc_bits);
assignin('base', 'data_bits', data_bits);
assignin('base', 'hamming_word', hamming_word);
assignin('base', 'code_word', code_word);
assignin('base', 'decoded_bits', decoded_bits);
assignin('base', 'decode_status', decode_status);
assignin('base', 'syndrome', syndrome);
assignin('base', 'corrected_word', corrected_word);

fprintf('[ECC] Создано %d исходных бит и закодировано в %d бит.\n', ...
    numel(data_bits), numel(code_word));
fprintf('Для Simulink входной вектор: data_bits; выходной кадр: code_word.\n');
fprintf('[ECC] Декодирование: %s, syndrome=%d, совпадение данных=%d.\n', ...
    decode_status, syndrome, isequal(decoded_bits, data_bits));
