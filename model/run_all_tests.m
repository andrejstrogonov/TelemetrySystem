%% run_all_tests.m
% Автоматический запуск тестов цифрового тракта для всех сценариев Owon

clearvars -except test_signals config; % Сохраняем загруженные сигналы
clc;

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
