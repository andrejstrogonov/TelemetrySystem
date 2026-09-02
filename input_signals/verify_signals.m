%% owon_verify_signals.m
%  Верификация всех 4 тестовых сигналов через ECC + CRC.
%  Прогоняет каждый кадр через ecc_hamming_decode и crc8_compute,
%  выводит таблицу PASS/FAIL.
%
%  Предварительно: owon_hds242s_config, generate_owon_test_signals

clear; clc;

if ~exist('config', 'var')
    run('owon_hds242s_config.m');
end

if ~exist('test_signals', 'var')
    load(config.paths.mat_file, 'test_signals');
    fprintf('[INFO] Загружен %s\n', config.paths.mat_file);
end

fprintf('\n=== ВЕРИФИКАЦИЯ ТЕСТОВЫХ СИГНАЛОВ ===\n\n');

%% ── Таблица ожидаемых результатов ──
tests = {
    '1. Идеальный',      test_signals.frame_ideal,  'no_error',       true;
    '2. Одиночная',      test_signals.frame_single, 'corrected',      true;
    '3. Двойная',        test_signals.frame_double, 'uncorrectable',  false;
    '4. Пакетная',       test_signals.frame_burst,   'uncorrectable',  false;
};

expected_headers = {'Тест', 'ECC статус', 'Syndrome', ...
                    'CRC', 'Ошибки', 'Результат'};
results = cell(numel(tests)+1, numel(expected_headers));
results(1,:) = expected_headers;

pass_count = 0;
details = struct();

for t = 1:numel(tests)
    frame_in = tests{t, 2};

    % ── ECC декодирование ──
    [data_out, ecc_status, syndrome, corrected_frame] = ...
        ecc_hamming_decode(frame_in, config);

    % ── CRC проверка ──
    payload_rcvd = data_out(1:config.frame.payload_bits);
    crc_rcvd     = data_out(config.frame.payload_bits+1:config.frame.data_bits);
    [crc_recomp, ~] = crc8_compute(payload_rcvd, ...
        config.crc.polynomial, config.crc.init, config.crc.xor_out);
    crc_ok = isequal(crc_rcvd, crc_recomp);

    % ── Позиции ошибок ──
    err_pos = find(frame_in ~= test_signals.frame_ideal);
    if isempty(err_pos)
        err_str = '—';
    else
        err_str = num2str(err_pos);
    end

    % ── Проверка ожиданий ──
    ecc_pass = strcmp(ecc_status, tests{t, 3});
    crc_pass = (crc_ok == tests{t, 4});
    test_pass = ecc_pass && crc_pass;

    if test_pass
        tag = 'PASS';
        pass_count = pass_count + 1;
    else
        tag = 'FAIL';
    end

    % ── Вывод в таблицу ──
    results(t+1, 1) = {tests{t, 1}};
    results(t+1, 2) = {ecc_status};
    results(t+1, 3) = {num2str(syndrome)};
    results(t+1, 4) = {ternary_str(crc_ok, 'OK', 'ERROR')};
    results(t+1, 5) = {err_str};
    results(t+1, 6) = {tag};

    % ── Детали ──
    details.(tests{t, 1}) = struct( ...
        'frame_in',       frame_in, ...
        'data_out',       data_out, ...
        'ecc_status',     ecc_status, ...
        'syndrome',       syndrome, ...
        'crc_ok',         crc_ok, ...
        'crc_received',   crc_rcvd, ...
        'crc_computed',   crc_recomp, ...
        'error_positions', err_pos, ...
        'test_pass',      test_pass);

    % ── Подробный вывод ──
    fprintf('─── %s ───\n', tests{t, 1});
    fprintf('  Frame IN:  %s\n', num2str(frame_in));
    fprintf('  ECC:       %s (syndrome=%d, ожид.=%s) %s\n', ...
        ecc_status, syndrome, tests{t, 3}, ...
        ternary_str(ecc_pass, [char(10003)], [char(10007)]));
    fprintf('  Data OUT:  %s\n', num2str(data_out));
    fprintf('  CRC recv:  %s\n', num2str(crc_rcvd));
    fprintf('  CRC calc:  %s\n', num2str(crc_recomp));
    fprintf('  CRC:       %s (ожид.=%s) %s\n', ...
        ternary_str(crc_ok, 'OK', 'ERROR'), ...
        ternary_str(tests{t, 4}, 'OK', 'ERROR'), ...
        ternary_str(crc_pass, [char(10003)], [char(10007)]));
    fprintf('  Errors:    @ %s\n', err_str);
    fprintf('  РЕЗУЛЬТАТ: [%s]\n\n', tag);
end

%% ── Печать сводной таблицы ──
fprintf('\n=== СВОДНАЯ ТАБЛИЦА ===\n\n');
for r = 1:size(results, 1)
    fprintf('%-18s | %-18s | %-8s | %-7s | %-18s | %-8s\n', ...
        results{r, 1}, results{r, 2}, results{r, 3}, ...
        results{r, 4}, results{r, 5}, results{r, 6});
    if r == 1
        fprintf('%s\n', repmat('-', 1, 90));
    end
end

%% ── Итог ──
fprintf('\n=== ИТОГ: %d / %d тестов пройдено ===\n', pass_count, numel(tests));

if pass_count == numel(tests)
    fprintf('\n  ВСЕ ТЕСТЫ ПРОЙДЕНЫ — сигналы корректны для HDS242S.\n');
else
    fprintf('\n  ЕСТЬ НЕ ПРОЙДЕННЫЕ ТЕСТЫ — проверьте логику ECC/CRC.\n');
end

%% ── Ожидаемая таблица для документации ──
fprintf('\n=== ОЖИДАЕМАЯ ТАБЛИЦА РЕЗУЛЬТАТОВ ===\n');
fprintf('+-------------------+------------------+-------------------+----------+\n');
fprintf('| Сигнал            | ecc_corrected    | ecc_uncorrectable | crc_ok   |\n');
fprintf('+-------------------+------------------+-------------------+----------+\n');
fprintf('| Идеал             |        0         |         0         |    1     |\n');
fprintf('| Single            |        1         |         0         |    1     |\n');
fprintf('| Double            |        0         |         1         |    0     |\n');
fprintf('| Burst             |        0         |         1         |    0     |\n');
fprintf('+-------------------+------------------+-------------------+----------+\n');

%% ── Сохранение результатов ──
verify_results = struct( ...
    'pass_count', pass_count, ...
    'total',     numel(tests), ...
    'all_pass',  pass_count == numel(tests), ...
    'details',   details, ...
    'table',     results, ...
    'timestamp', datestr(now, 'yyyy-mm-dd HH:MM:SS'));

save(fullfile(config.paths.output_dir, 'verify_results.mat'), 'verify_results');
fprintf('\n[SAVED] %s/verify_results.mat\n', config.paths.output_dir);

%% ── Вспомогательные функции ──
function s = ternary_str(cond, a, b)
    if cond
        s = a;
    else
        s = b;
    end
end
