%% run_all_tests.m
% Автоматический запуск тестов цифрового тракта для всех сценариев Owon

% ИСПРАВЛЕНО: Добавлены маски ts_* и nrz_* для сохранения всех тестовых сигналов
clearvars -except test_signals config ts_* nrz_*; 
clc;

% init_crc_vars.m
% Инициализация переменных для блока General CRC Syndrome Detector HDL Optimized
dimension = 32;
hexPoly = '04C11DB7';
decPoly = hex2dec(hexPoly);
polyBits = de2bi(decPoly, dimension, 'left-msb');
polyCoeffs = [1, polyBits];

if length(polyCoeffs) ~= dimension+1
    error('Критическая ошибка: polyCoeffs имеет длину %d, а должна быть 33! Проверьте код.', length(polyCoeffs));
end

initState = ones(1, dimension);
finalXor = zeros(1, dimension);

fprintf('Переменные успешно инициализированы:\n');
fprintf('  polyCoeffs: длина %d (ожидалось 33)\n', length(polyCoeffs));
fprintf('  initState:  длина %d (ожидалось 32)\n', length(initState));
fprintf('  finalXor:   длина %d (ожидалось 32)\n', length(finalXor));

model_name = 'main_signal_system'; 
test_labels = {'Идеал (Эталон)', 'Одиночная ошибка', 'Двойная ошибка', 'Пакетный сбой'};

fprintf('=== ЗАПУСК АВТОМАТИЧЕСКОЙ ВЕРИФИКАЦИИ ЦИФРОВОГО ТРАКТА ===\n\n');

load_system(model_name);

for id = 1:4
    fprintf('[ТЕСТ %d/4] Запуск сценария: %s...\n', id, test_labels{id});
    
    assignin('base', 'Scenario_ID', id);
    
    % Запуск симуляции
    sim_out = sim(model_name, 'CaptureErrors', 'on');
    
    if isempty(sim_out.ErrorMessage)
        fprintf('  [СТАТУС]: Успешно завершено.\n');
        
        %% === БЛОК ПОСТРОЕНИЯ ГРАФИКОВ СБОЕВ ===
        try
            % 1. Получаем доступ к логированным сигналам (по умолчанию это logsout)
            logs = sim_out.logsout;
            
            % !!! ВНИМАНИЕ: Замените 'input_signal' и 'crc_error_flag' на реальные 
            % имена сигналов, которые у вас настроены на логирование (Data Logging) в модели.
            sig_data = logs.get('input_signal').Values;      % Входной цифровой сигнал
            err_data = logs.get('crc_error_flag').Values;  % Флаг ошибки (0 - норм, 1 - сбой)
            
            % 2. Создаем новое окно для каждого теста
            figure('Name', sprintf('Сценарий: %s', test_labels{id}), 'Color', 'w');
            
            % Верхний подграфик: Исходный сигнал/тракт
            subplot(2,1,1);
            plot(sig_data.Time, sig_data.Data, 'LineWidth', 1.5, 'Color', [0 0.4470 0.7410]);
            grid on;
            title(sprintf('Входной сигнал (Тест: %s)', test_labels{id}));
            ylabel('Амплитуда / Бит');
            
            % Нижний подграфик: Флаг фиксации ошибок
            subplot(2,1,2);
            stem(err_data.Time, err_data.Data, 'LineWidth', 1.5, 'Color', [0.8500 0.3250 0.0980], 'Marker', 'x');
            grid on;
            title('Маркеры фиксации сбоев блоком CRC');
            xlabel('Время (с)');
            ylabel('Статус сбоя (0/1)');
            ylim([-0.2 1.2]); % Ограничим по высоте для наглядности флага
            
            fprintf('  [ГРАФИК]: Окно визуализации сбоев успешно создано.\n\n');
            
        catch ME_vis
            fprintf('  [ПРЕДУПРЕЖДЕНИЕ]: Не удалось построить график. Проверьте имена сигналов в логах.\n');
            fprintf('  Детали: %s\n\n', ME_vis.message);
        end
        %% ======================================
        
    else
        fprintf('  [ОШИБКА]: Тест зафиксировал критический сбой алгоритма!\n');
        fprintf('  Детали: %s\n\n', sim_out.ErrorMessage);
    end
end

fprintf('=== ВЕРИФИКАЦИЯ ЗАВЕРШЕНА ===\n');
