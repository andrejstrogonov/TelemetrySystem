%% run_all_tests.m
% Автоматический запуск тестов цифрового тракта для всех сценариев Owon

clearvars -except test_signals config; % Сохраняем загруженные сигналы
clc;

% init_crc_vars.m
% Инициализация переменных для блока General CRC Syndrome Detector HDL Optimized

% Полином CRC-32 (Ethernet): длина 33 (степень 32)
 % polyCoeffs = [1 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 1 1 0 0 0 0 0 1 0 0 1];
 dimension = 32;
 hexPoly = '04C11DB7';
 decPoly = hex2dec(hexPoly);
 polyBits = de2bi(decPoly, dimension, 'left-msb');
 polyCoeffs = [1, polyBits];


% Проверка длины сразу после создания (для отладки)
if length(polyCoeffs) ~= dimension+1
    error('Критическая ошибка: polyCoeffs имеет длину %d, а должна быть 33! Проверьте код.', length(polyCoeffs));
end

% CRC-32/MPEG-2: initial state is 0xFFFFFFFF, represented MSB first.
initState = ones(1, dimension);

% CRC-32/MPEG-2: no final XOR.
finalXor = zeros(1, dimension);

fprintf('Переменные успешно инициализированы:\n');
fprintf('  polyCoeffs: длина %d (ожидалось 33)\n', length(polyCoeffs));
fprintf('  initState:  длина %d (ожидалось 32)\n', length(initState));
fprintf('  finalXor:   длина %d (ожидалось 32)\n', length(finalXor));

% Название вашей интеграционной или сигнальной модели Simulink (без .slx)
model_name = 'main_signal_system'; 

% Массив названий тестов для красивого вывода в лог
test_labels = {'Идеал (Эталон)', 'Одиночная ошибка', 'Двойная ошибка', 'Пакетный сбой'};

fprintf('=== ЗАПУСК АВТОМАТИЧЕСКОЙ ВЕРИФИКАЦИИ ЦИФРОВОГО ТРАКТА ===\n\n');

% Загружаем модель в память без открытия графического окна (для ускорения)
load_system(model_name);

for id = 1:4
    fprintf('[ТЕСТ %d/4] Запуск сценария: %s...\n', id, test_labels{id});
    
    % Передаем ID сценария в Base Workspace, чтобы Simulink его увидел
    assignin('base', 'Scenario_ID', id);
    
    % Запуск симуляции с подавлением вывода лишних логов в консоль
    sim_out = sim(model_name, 'CaptureErrors', 'on');
    
    % Проверяем, не упала ли симуляция из-за блоков Assertion (если они настроены)
    if isempty(sim_out.ErrorMessage)
        fprintf('  [СТАТУС]: Успешно завершено.\n\n');
    else
        fprintf('  [ОШИБКА]: Тест зафиксировал критический сбой алгоритма!\n');
        fprintf('  Детали: %s\n\n', sim_out.ErrorMessage);
    end
    
    % Здесь можно сохранить графики, если у вас в модели есть блоки Scope/To Workspace
    % Пример: save(sprintf('test_result_scen_%d.mat', id), 'sim_out');
end

fprintf('=== ВЕРИФИКАЦИЯ ЗАВЕРШЕНА ===\n');
