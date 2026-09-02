%% generate_owon_test_signals.m
%  Главный скрипт генерации 4 тестовых сигналов для Owon HDS242S.
%
%  Производит:
%    1. 4 битовых кадра (идеал / single / double / burst)
%    2. NRZ-осциллограммы (8192 точки, 14-бит ЦАП)
%    3. CSV-файлы для внешнего ЦАП
%    4. SCPI-скрипты для HDS242S
%    5. Графики с подсветкой ошибок
%    6. .mat-файл со всеми данными
%
%  Предварительно запустить: owon_hds242s_config

clear; clc; close all;

if ~exist('config', 'var')
    run('owon_hds242s_config.m');
end

%% ── Создание папок вывода ──
dirs = {config.paths.output_dir, config.paths.csv_dir, ...
        config.paths.scpi_dir, config.paths.simulink_dir};
for d = 1:numel(dirs)
    if ~exist(dirs{d}, 'dir'), mkdir(dirs{d}); end
end

fprintf('\n=== ГЕНЕРАЦИЯ ТЕСТОВЫХ СИГНАЛОВ ===\n\n');

%% ── 1. Идеальный сигнал (эталон) ──
rng(config.test.payload_seed);
payload = randi([0 1], 1, config.frame.payload_bits);

[crc_bits, ~] = crc8_compute(payload, ...
    config.crc.polynomial, config.crc.init, config.crc.xor_out);

data_24 = [payload, crc_bits];

[frame_ideal, ~] = ecc_hamming_encode(data_24, config);

fprintf('[1/4] Идеальный кадр:\n');
fprintf('  Payload:  %s\n', num2str(payload));
fprintf('  CRC-8:    %s\n', num2str(crc_bits));
fprintf('  Frame:    %s\n', num2str(frame_ideal));

%% ── 2. Одиночная битовая ошибка ──
frame_single = frame_ideal;
pos_s = config.test.single_bit_pos;
frame_single(pos_s) = 1 - frame_single(pos_s);

fprintf('\n[2/4] Single-bit error @ bit %d:\n', pos_s);
fprintf('  Frame:    %s\n', num2str(frame_single));
fprintf('  Diff:     %s\n', num2str(frame_single ~= frame_ideal));

%% ── 3. Двойная битовая ошибка ──
frame_double = frame_ideal;
pos_d = config.test.double_bit_pos;
frame_double(pos_d(1)) = 1 - frame_double(pos_d(1));
frame_double(pos_d(2)) = 1 - frame_double(pos_d(2));

fprintf('\n[3/4] Double-bit error @ bits %d,%d:\n', pos_d(1), pos_d(2));
fprintf('  Frame:    %s\n', num2str(frame_double));
fprintf('  Diff:     %s\n', num2str(frame_double ~= frame_ideal));

%% ── 4. Пакетная ошибка (burst 8 бит) ──
frame_burst = frame_ideal;
bs  = config.test.burst_start;
bl  = config.test.burst_length;
frame_burst(bs:bs+bl-1) = 1 - frame_burst(bs:bs+bl-1);

fprintf('\n[4/4] Burst error @ bits %d..%d (%d бит):\n', bs, bs+bl-1, bl);
fprintf('  Frame:    %s\n', num2str(frame_burst));
fprintf('  Diff:     %s\n', num2str(frame_burst ~= frame_ideal));

%% ── Преобразование в NRZ ──
frames   = {frame_ideal, frame_single, frame_double, frame_burst};
names    = {'ideal', 'single', 'double', 'burst'};
labels   = {'1. Идеальный (эталон)', '2. Одиночная ошибка', ...
            '3. Двойная ошибка', '4. Пакетная ошибка (burst 8)'};
colors   = {[0 0.7 0], [1 0.85 0], [1 0.5 0], [0.9 0.1 0]};

nrz_dac      = cell(1, 4);
nrz_voltage  = cell(1, 4);
time_axis    = cell(1, 4);

for k = 1:4
    [nrz_dac{k}, nrz_voltage{k}, time_axis{k}] = ...
        bits_to_nrz(frames{k}, config);
    fprintf('\n[NRZ] %s: %d точек, %d..%d DAC\n', ...
        names{k}, numel(nrz_dac{k}), min(nrz_dac{k}), max(nrz_dac{k}));
end

%% ── Экспорт CSV ──
for k = 1:4
    csv_path = fullfile(config.paths.csv_dir, sprintf('nrz_%s.csv', names{k}));
    csv_data = [(1:numel(nrz_dac{k}))', nrz_dac{k}(:)];
    writematrix(csv_data, csv_path);
    fprintf('[CSV] %s\n', csv_path);
end

%% ── Генерация SCPI-скриптов ──
% Тесты 1-3: квадратный тактовый сигнал
for k = 1:3
    scpi_path = fullfile(config.paths.scpi_dir, sprintf('scpi_%s.txt', names{k}));
    fid = fopen(scpi_path, 'w');
    for c = 1:numel(config.scpi.templates.clock)
        fprintf(fid, '%s\n', config.scpi.templates.clock{c});
    end
    fprintf(fid, '%% Test: %s (bitrate %d bit/s)\n', labels{k}, config.nrz.bitrate);
    fclose(fid);
    fprintf('[SCPI] %s\n', scpi_path);
end

% Тест 4: имитация помехи через Pulse
scpi_path = fullfile(config.paths.scpi_dir, 'scpi_burst.txt');
fid = fopen(scpi_path, 'w');
for c = 1:numel(config.scpi.templates.burst)
    fprintf(fid, '%s\n', config.scpi.templates.burst{c});
end
fprintf(fid, '%% Test: %s (burst %d bits)\n', labels{4}, config.test.burst_length);
fclose(fid);
fprintf('[SCPI] %s\n', scpi_path);

% Калибровочный скрипт
scpi_path = fullfile(config.paths.scpi_dir, 'scpi_calibration.txt');
fid = fopen(scpi_path, 'w');
for c = 1:numel(config.scpi.templates.calib)
    fprintf(fid, '%s\n', config.scpi.templates.calib{c});
end
fclose(fid);
fprintf('[SCPI] %s\n', scpi_path);

%% ── Сохранение .mat ──
test_signals = struct( ...
    'frame_ideal',  frame_ideal, ...
    'frame_single', frame_single, ...
    'frame_double', frame_double, ...
    'frame_burst',  frame_burst, ...
    'payload',      payload, ...
    'crc_bits',     crc_bits, ...
    'data_24',      data_24, ...
    'nrz_dac',      {nrz_dac}, ...
    'nrz_voltage',  {nrz_voltage}, ...
    'time_axis',    {time_axis}, ...
    'names',        {names}, ...
    'labels',       {labels}, ...
    'config',       config, ...
    'metadata', struct( ...
        'single_bit_pos', config.test.single_bit_pos, ...
        'double_bit_pos', config.test.double_bit_pos, ...
        'burst_start',    config.test.burst_start, ...
        'burst_length',   config.test.burst_length, ...
        'payload_seed',   config.test.payload_seed, ...
        'generated',      datestr(now, 'yyyy-mm-dd HH:MM:SS')));

save(config.paths.mat_file, 'test_signals');
fprintf('\n[MAT] %s\n', config.paths.mat_file);

%% ── Визуализация ──
figure('Name', 'Owon HDS242S — Тестовые сигналы', ...
       'Position', [50 50 1400 900]);

for k = 1:4
    % ── Битовый кадр ──
    subplot(4, 2, 2*k-1);
    stem(1:32, frames{k}, 'filled', 'MarkerSize', 5, ...
         'Color', colors{k});
    hold on;
    diff_mask = (frames{k} ~= frame_ideal);
    if any(diff_mask)
        err_pos = find(diff_mask);
        stem(err_pos, frames{k}(err_pos), 'filled', ...
             'MarkerSize', 9, 'Color', [1 0 0], 'LineWidth', 2);
        for e = 1:numel(err_pos)
            text(err_pos(e), 1.15, num2str(err_pos(e)), ...
                 'Color', [1 0 0], 'FontSize', 8, 'HorizontalAlignment', 'center');
        end
    end
    title(labels{k}, 'FontSize', 10, 'Color', colors{k});
    xlabel('Бит'); ylabel('Значение');
    ylim([-0.5 1.5]); yticks([0 1]); grid on;
    xlim([0 33]);

    % ── NRZ-сигнал ──
    subplot(4, 2, 2*k);
    % Показываем первые 1024 точек (4 бита) для наглядности
    plot_pts = min(1024, numel(nrz_voltage{k}));
    plot(time_axis{k}(1:plot_pts)*1e6, nrz_voltage{k}(1:plot_pts), ...
         'Color', colors{k}, 'LineWidth', 1.2);
    hold on;
    % Подсветка ошибочных битовых интервалов
    ppb = config.nrz.points_per_bit;
    diff_mask = (frames{k} ~= frame_ideal);
    if any(diff_mask)
        err_pos = find(diff_mask);
        for e = 1:numel(err_pos)
            x1 = (err_pos(e)-1) * ppb;
            x2 = err_pos(e) * ppb;
            if x2 <= plot_pts
                yl = ylim;
                patch([time_axis{k}(x1+1) time_axis{k}(x2) time_axis{k}(x2) time_axis{k}(x1+1)], ...
                      [yl(1) yl(1) yl(2) yl(2)], [1 0.3 0], ...
                      'FaceAlpha', 0.15, 'EdgeColor', 'none');
            end
        end
    end
    title(sprintf('NRZ: %s (%d точек, %d-бит ЦАП)', ...
        names{k}, config.owon.awg_depth, config.owon.dac_bits), ...
        'FontSize', 9);
    xlabel('Время, мкс'); ylabel('Напряжение, В');
    ylim([-0.3 3.6]); grid on;
end

sgtitle('Owon HDS242S — Тестовые сигналы ECC/CRC', 'FontSize', 13, 'FontWeight', 'bold');
saveas(gcf, config.paths.plot_file);
fprintf('[PNG] %s\n', config.paths.plot_file);

%% ── Сводка ──
fprintf('\n=== СВОДКА ===\n');
fprintf('  Кадр:     %d бит\n', config.frame.total);
fprintf('  Payload:  %s\n', num2str(payload));
fprintf('  CRC-8:    %s\n', num2str(crc_bits));
fprintf('  Hamming:  (%d,%d) SEC-DED\n', ...
    config.hamming.code_length, config.hamming.info_length);
fprintf('\n  Ошибки:\n');
fprintf('  Single @ bit %d\n', config.test.single_bit_pos);
fprintf('  Double @ bits %d, %d\n', config.test.double_bit_pos);
fprintf('  Burst  @ bits %d..%d (%d бит)\n', ...
    config.test.burst_start, ...
    config.test.burst_start + config.test.burst_length - 1, ...
    config.test.burst_length);
fprintf('\n  Файлы:\n');
fprintf('  MAT:  %s\n', config.paths.mat_file);
fprintf('  PNG:  %s\n', config.paths.plot_file);
fprintf('  CSV:  %s/*.csv\n', config.paths.csv_dir);
fprintf('  SCPI: %s/*.txt\n', config.paths.scpi_dir);
fprintf('\nДалее: owon_verify_signals для проверки.\n');
