%% owon_export_for_simulink.m
%  Загрузка NRZ-сигналов в Workspace как timeseries и структуры
%  для блоков From Workspace в Simulink с выравниванием размерностей.
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

    % NRZ-напряжение как timeseries (8192 точки) — СКАЛЯРНЫЙ ПОТОК [1x1]
    ts_nrz = timeseries(test_signals.nrz_voltage{k}(:), ...
                        test_signals.time_axis{k}(:), ...
                        'Name', sprintf('nrz_%s', names{k}));

    % Сохраняем в Workspace
    assignin('base', ts_names{k}, ts_bit);
    assignin('base', sprintf('nrz_%s', names{k}), ts_nrz);

    fprintf('[SIMULINK] %s  →  From Workspace: Variable = %s\n', ...
        test_signals.labels{k}, ts_names{k});
    fprintf('           %s  →  From Workspace: Variable = nrz_%s\n', ...
        test_signals.labels{k}, names{k});
end

% Создаем базовую переменную nrz_ideal для первого теста, чтобы схема сразу запускалась
assignin('base', 'nrz_ideal', evalin('base', 'nrz_ideal'));

%% ── Комбинированный timeseries (все 4 кадра последовательно) ──
% Чтобы Simulink понимал вектор размера 32 из структуры, 
% значения должны быть упакованы в массив размерностью [32 x 1 x Количество_Шагов]
all_frames = [test_signals.frame_ideal, ...
              test_signals.frame_single, ...
              test_signals.frame_double, ...
              test_signals.frame_burst]; % Размер [32 x 4]

% Преобразуем в формат [32 x 1 x 4]
frame_length = config.frame.total;
all_frames_reshaped = zeros(frame_length, 1, 4);
for k = 1:4
    all_frames_reshaped(:, 1, k) = all_frames(:, k);
end

% Формируем структуру структуры, жестко задавая векторную размерность
ts_all = struct();
ts_all.time = (0:3)';
ts_all.signals.values = all_frames_reshaped;
ts_all.signals.dimensions = frame_length;

assignin('base', 'ts_all_frames', ts_all);
fprintf('\n[SIMULINK] ts_all_frames → From Workspace (4 кадра × %d бита, размерность зафиксирована)\n', frame_length);

%% ── NRZ-комбинация для аналогового ввода ──
nrz_all = [test_signals.nrz_voltage{1}(:); ...
           test_signals.nrz_voltage{2}(:); ...
           test_signals.nrz_voltage{3}(:); ...
           test_signals.nrz_voltage{4}(:)];

ts_nrz_all = timeseries(nrz_all, ...
    (0:numel(nrz_all)-1) / config.nrz.sample_rate, ...
    'Name', 'nrz_all_tests');

assignin('base', 'ts_nrz_all', ts_nrz_all);
fprintf('[SIMULINK] ts_nrz_all → From Workspace (NRZ всех 4 тестов)\n');

%% ── Проверка Workspace ──
fprintf('\nГотово. Переменные в Workspace:\n');
whos ts_ideal ts_single ts_double ts_burst ts_all_frames nrz_ideal ts_nrz_all