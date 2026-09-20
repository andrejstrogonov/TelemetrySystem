%% run_all_tests.m
% Автоматический запуск тестов цифрового и аналогового трактов Owon

% Защищаем переменные сигналов From Workspace от очистки памяти
clearvars -except test_signals config ts_* nrz_*; 
clc;

% Настройки инициализации CRC (в строгом соответствии с блоками вашей модели)
dimension = 32;
hexPoly = '04C11DB7';
decPoly = hex2dec(hexPoly);
polyBits = de2bi(decPoly, dimension, 'left-msb');
polyCoeffs = [1, polyBits];

if length(polyCoeffs) ~= dimension+1
    error('Критическая ошибка: polyCoeffs имеет длину %d, а должна быть 33!', length(polyCoeffs));
end

initState = 1;                
finalXor = ones(1, dimension); 

model_name = 'main_signal_system'; 
test_labels = {'Идеал (Эталон)', 'Одиночная ошибка', 'Двойная ошибка', 'Пакетный сбой'};

fprintf('=== ЗАПУСК КОМПЛЕКСНОЙ АВТОМАТИЧЕСКОЙ ВЕРИФИКАЦИИ ТРАКТОВ ===\n\n');

load_system(model_name);

for id = 1:4
    fprintf('[ТЕСТ %d/4] Запуск сценария: %s...\n', id, test_labels{id});
    
    sim_in = Simulink.SimulationInput(model_name);
    sim_in = sim_in.setVariable('Scenario_ID', id);
    sim_in = sim_in.setBlockParameter([model_name '/Scenario_ID'], 'Value', num2str(id));
    sim_in = sim_in.setModelParameter('CaptureErrors', 'on');
    
    sim_out = sim(sim_in);
    
    if isempty(sim_out.ErrorMessage)
        fprintf('  [СТАТУС]: Успешно завершено.\n');
        
        %% === БЛОК ПОСТРОЕНИЯ КОМПЛЕКСНЫХ ГРАФИКОВ ===
        try
            logs = sim_out.logsout;
            
            %% 1. ОТРИСОВКА ЦИФРОВОГО ТРАКТА (TS)
            % ИСПРАВЛЕНО: Безопасный поиск элементов в Dataset через метод find() вместо has/hasElement
            ts_in_element = logs.find('Name', 'ts_switch');
            ts_out_element = logs.find('Name', 'ts_crc_out');
            
            if ~isempty(ts_in_element) && ~isempty(ts_out_element)
                ts_in_obj = ts_in_element{1}.Values;
                ts_out_obj = ts_out_element{1}.Values;
                
                ts_in_fixed = squeeze(ts_in_obj.Data);
                ts_out_fixed = squeeze(ts_out_obj.Data);
                
                figure('Name', sprintf('TS (Цифра) - Сценарий: %s', test_labels{id}), 'Color', 'w');
                
                subplot(2,1,1);
                plot(ts_in_obj.Time, ts_in_fixed, 'LineWidth', 1.5, 'Color', [0 0.4470 0.7410]);
                grid on; 
                title(sprintf('Входная маска цифровых сбоев ts\\_switch (Тест: %s)', test_labels{id}));
                ylabel('Амплитуда');
                
                subplot(2,1,2);
                % ИСПРАВЛЕНО: Для накопительного счетчика count_hit строим ступенчатый график stairs
                stairs(ts_out_obj.Time, ts_out_fixed, 'LineWidth', 1.5, 'Color', [0.8500 0.3250 0.0980]);
                grid on; 
                title('Показания счетчика ошибок TS (Сигнал ts\_crc\_out)');
                xlabel('Время (с)'); 
                ylabel('Кол-во ошибок');
                
                % Настройка лимитов для оси Y
                if max(ts_out_fixed) > 0
                    ylim([-0.5 max(ts_out_fixed) + 1.5]);
                else
                    ylim([-0.5 2.5]);
                end
                
                fprintf('  [ГРАФИК TS]: Окно визуализации цифрового тракта успешно создано.\n');
            else
                fprintf('  [ПРЕДУПРЕЖДЕНИЕ TS]: Линии ''ts_switch'' или ''ts_crc_out'' не найдены в логах.\n');
            end
            
            %% 2. ОТРИСОВКА АНАЛОГОВОГО ТРАКТА (NRZ)
            % ИСПРАВЛЕНО: Безопасный поиск элементов в Dataset через метод find() вместо has/hasElement
            nrz_in_element = logs.find('Name', 'nrz_switch');
            nrz_out_element = logs.find('Name', 'nrz_crc_out');
            
            if ~isempty(nrz_in_element) && ~isempty(nrz_out_element)
                nrz_in_obj = nrz_in_element{1}.Values;
                nrz_out_obj = nrz_out_element{1}.Values;
                
                nrz_in_fixed = squeeze(nrz_in_obj.Data);
                nrz_out_fixed = squeeze(nrz_out_obj.Data);
                
                figure('Name', sprintf('NRZ (Аналог) - Сценарий: %s', test_labels{id}), 'Color', 'w');
                
                subplot(2,1,1);
                plot(nrz_in_obj.Time, nrz_in_fixed, 'LineWidth', 1.5, 'Color', [0.4660 0.6740 0.1880]);
                grid on; 
                title(sprintf('Входная маска аналоговых сбоев nrz\\_switch (Тест: %s)', test_labels{id}));
                ylabel('Амплитуда');
                
                subplot(2,1,2);
                % ИСПРАВЛЕНО: Для накопительного счетчика count_hit строим ступенчатый график stairs
                stairs(nrz_out_obj.Time, nrz_out_fixed, 'LineWidth', 1.5, 'Color', [0.4940 0.1840 0.5560]);
                grid on; 
                title('Показания счетчика ошибок NRZ (Сигнал nrz\_crc\_out)');
                xlabel('Время (с)'); 
                ylabel('Кол-во ошибок');
                
                % Настройка лимитов для оси Y
                if max(nrz_out_fixed) > 0
                    ylim([-0.5 max(nrz_out_fixed) + 1.5]);
                else
                    ylim([-0.5 2.5]);
                end
                
                fprintf('  [ГРАФИК NRZ]: Окно визуализации аналогового тракта успешно создано.\n');
            else
                fprintf('  [ПРЕДУПРЕЖДЕНИЕ NRZ]: Линии ''nrz_switch'' или ''nrz_crc_out'' не найдены в логах.\n');
            end
            fprintf('\n');
            
        catch ME_vis
            fprintf('  [ПРЕДУПРЕЖДЕНИЕ]: Ошибка в блоке построения графиков.\n');
            fprintf('  Детали: %s\n\n', ME_vis.message);
        end
        %% ======================================
        
    else
        fprintf('  [ОШИБКА]: Тест зафиксировал критический сбой!\n');
        fprintf('  Детали: %s\n\n', sim_out.ErrorMessage);
    end
end

fprintf('=== КОМПЛЕКСНАЯ ВЕРИФИКАЦИЯ ЗАВЕРШЕНА ===\n');
