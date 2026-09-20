%% run_all_tests.m
% Автоматический запуск тестов цифрового тракта для всех сценариев Owon

% ИСПРАВЛЕНО: Сохраняем переменные окружения
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
    
    % 1. Инициализируем объект конфигурации симуляции
    sim_in = Simulink.SimulationInput(model_name);
    
    % Передаем переменную Scenario_ID в локальный воркспейс симуляции
    sim_in = sim_in.setVariable('Scenario_ID', id);
    
    % РЕШЕНИЕ ПРОБЛЕМЫ ИДЕНТИЧНЫХ КАРТИНОК:
    % Принудительно заставляем блок Constant, управляющий переключателем ts_switch,
    % принимать текущее значение шага цикла (id).
    % ВНИМАНИЕ: Если блок константы на схеме называется не Scenario_ID, замените имя ниже.
    sim_in = sim_in.setBlockParameter([model_name '/Scenario_ID'], 'Value', num2str(id));
    
    % Включаем безопасный перехват ошибок симуляции внутри объекта sim_in
    sim_in = sim_in.setModelParameter('CaptureErrors', 'on');
    
    % 2. Запуск симуляции с обновленным объектом настроек
    sim_out = sim(sim_in);
    
    if isempty(sim_out.ErrorMessage)
        fprintf('  [СТАТУС]: Успешно завершено.\n');
        
        %% === БЛОК ПОСТРОЕНИЯ ГРАФИКОВ СБОЕВ ===
        try
            % Доступаемся до сохраненного Dataset сигналов
            logs = sim_out.logsout;
            
            % Извлекаем объекты сигналов
            sig_obj = logs.get('ts_switch').Values;  % Входной цифровой сигнал
            err_obj = logs.get('crc_out').Values;    % Выходной флаг сбоя CRC
            
            % ИСПРАВЛЕНО РАНЕЕ: Принудительный squeeze для удаления 3D размерностей (1x1xN -> Nx1)
            sig_data_fixed = squeeze(sig_obj.Data);
            err_data_fixed = squeeze(err_obj.Data);
            
            % Создаем новое окно для каждого теста
            figure('Name', sprintf('Сценарий: %s', test_labels{id}), 'Color', 'w');
            
            % Верхний подграфик: Входной сигнал
            subplot(2,1,1);
            plot(sig_obj.Time, sig_data_fixed, 'LineWidth', 1.5, 'Color', [0 0.4470 0.7410]);
            grid on;
            title(sprintf('Входной сигнал ts\\_switch (Тест: %s)', test_labels{id}));
            ylabel('Амплитуда / Бит');
            
            % Нижний подграфик: Выходной сигнал / статус CRC
            subplot(2,1,2);
            stem(err_obj.Time, err_data_fixed, 'LineWidth', 1.5, 'Color', [0.8500 0.3250 0.0980], 'Marker', 'x');
            grid on;
            title('Выходной сигнал фиксации сбоев crc\\_out');
            xlabel('Время (с)');
            ylabel('Статус сбоя');
            
            % Динамическая настройка лимитов по оси Y для бинарных состояний
            if max(err_data_fixed) <= 1 && min(err_data_fixed) >= 0
                ylim([-0.2 1.2]); 
            end
            
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
