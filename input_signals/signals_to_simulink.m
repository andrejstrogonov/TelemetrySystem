%% owon_export_for_simulink.m
%  Загрузка NRZ-сигналов в Workspace как timeseries
%  для блоков From Workspace в Simulink.
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

fprintf('\n=== ЭКСПОРТ ДЛЯ SIMULINK ===\n\n');

%% ── Создание timeseries для каждого сигнала ──
names   = test_signals.names;
ts_names = {'ts_ideal', 'ts_single', 'ts_double', 'ts_burst'};

for k = 1:4
    % Битовый кадр как timeseries (1 значение на такт)
    ts_bit = timeseries(test_signals.(sprintf('frame_%s', names{k})), ...
                        0:31, 'Name', ts_names{k});

    % NRZ-напряжение как timeseries (8192 точки)
    ts_nrz = timeseries(test_signals.nrz_voltage{k}, ...
                        test_signals.time_axis{k}, ...
                        'Name', sprintf('nrz_%s', names{k}));

    % Сохраняем в Workspace
    assignin('base', ts_names{k}, ts_bit);
    assignin('base', sprintf('nrz_%s', names{k}), ts_nrz);

    fprintf('[SIMULINK] %s  →  From Workspace: Variable = %s\n', ...
        test_signals.labels{k}, ts_names{k});
    fprintf('           %s  →  From Workspace: Variable = nrz_%s\n', ...
        test_signals.labels{k}, names{k});
end

%% ── Комбинированный timeseries (все 4 кадра последовательно) ──
all_frames = [test_signals.frame_ideal; ...
              test_signals.frame_single; ...
              test_signals.frame_double; ...
              test_signals.frame_burst];

% Время: 4 такта, каждый кадр — 1 такт (dt = 1)
ts_all = struct();
ts_all.time = (0:3)';
ts_all.signals.values = all_frames;
ts_all.signals.dimensions = 32;

assignin('base', 'ts_all_frames', ts_all);
fprintf('\n[SIMULINK] ts_all_frames → From Workspace (4 кадра × 32 бита)\n');

%% ── NRZ-комбинация для аналогового ввода ──
nrz_all = [test_signals.nrz_voltage{1}, ...
           test_signals.nrz_voltage{2}, ...
           test_signals.nrz_voltage{3}, ...
           test_signals.nrz_voltage{4}];

ts_nrz_all = timeseries(nrz_all, ...
    (0:numel(nrz_all)-1) / config.nrz.sample_rate, ...
    'Name', 'nrz_all_tests');

assignin('base', 'ts_nrz_all', ts_nrz_all);
fprintf('[SIMULINK] ts_nrz_all → From Workspace (NRZ всех 4 тестов)\n');

%% ── Инструкция по Simulink ──
fprintf('\n=== ИНСТРУКЦИЯ SIMULINK ===\n');
fprintf('  1. Блок From Workspace:\n');
fprintf('     Variable name: ts_all_frames\n');
fprintf('     Sample time: 1 (дискретный)\n');
fprintf('     Interpolate: OFF (для цифровых данных)\n');
fprintf('     Form output: Array\n\n');
fprintf('  2. Для NRZ-сигнала (аналоговый вход):\n');
fprintf('     Variable name: nrz_ideal (или nrz_all)\n');
fprintf('     Sample time: 1/%d\n', config.nrz.sample_rate);
fprintf('     Interpolate: ON\n\n');
fprintf('  3. Подключение блоков:\n');
fprintf('     ts_all_frames → ECC_Chain → data_out[24] → CRC_Chain → флаги\n');
fprintf('     ECC_Chain: ecc_corrected, ecc_uncorrectable\n');
fprintf('     CRC_Chain: crc_ok, crc_error\n\n');
fprintf('  4. Мониторинг:\n');
fprintf('     Display: data_out, ecc_corrected, ecc_uncorrectable, crc_ok\n');
fprintf('     Lamp: зелёный = OK, жёлтый = corrected, красный = error\n');
fprintf('     Scope: флаги во времени\n\n');
fprintf('Готово. Переменные в Workspace:\n');
whos ts_ideal ts_single ts_double ts_burst ts_all_frames ts_nrz_all
