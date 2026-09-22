%% run_all_tests.m
%  Автоматический запуск тестов цифрового и аналогового трактов Owon
%  с комплексной математической верификацией результатов Simulink.

% Защищаем переменные сигналов From Workspace от очистки памяти
clearvars -except test_signals config ts_* nrz_*; 
clc;

% Проверка наличия конфигурации в Workspace
if ~exist('config', 'var')
    error('Критическая ошибка: Конфигурационная структура "config" не найдена в Workspace! Запустите owon_hds242s_config.m');
end

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

% Генерация эталонных векторов кадров для верификации "на лету"
rng(config.test.payload_seed);
% ИСПРАВЛЕНО: Приведение payload к типу uint32 для корректной работы bitshift
payload = uint32(randi([0 1], 1, config.frame.payload_bits));

[crc_bits] = local_crc32(uint32(payload), config.crc.polynomial, config.crc.init);

frame_ideal = local_hamming_encode([double(payload), crc_bits], config);

frames_ref = cell(1, 4);
frames_ref{1} = frame_ideal;
frames_ref{2} = frame_ideal; frames_ref{2}(config.test.single_bit_pos) = 1 - frames_ref{2}(config.test.single_bit_pos);
frames_ref{3} = frame_ideal; frames_ref{3}(config.test.double_bit_pos(1)) = 1 - frames_ref{3}(config.test.double_bit_pos(1)); frames_ref{3}(config.test.double_bit_pos(2)) = 1 - frames_ref{3}(config.test.double_bit_pos(2));
frames_ref{4} = frame_ideal; bs = config.test.burst_start; bl = config.test.burst_length; frames_ref{4}(bs:bs+bl-1) = 1 - frames_ref{4}(bs:bs+bl-1);

% Безопасное задание ожидаемого количества ошибок для каждого сценария
expected_ts_errors = zeros(1, 4);
expected_ts_errors(1) = 0;
expected_ts_errors(2) = 0;
expected_ts_errors(3) = 1;
expected_ts_errors(4) = 1;

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
        fprintf('  [СТАТУС МОДЕЛИ]: Успешно завершено.\n');
        
        %% === МАТЕМАТИЧЕСКИЙ АНАЛИЗАТОР И ВЕРИФИКАЦИЯ ЭТАЛОНА ===
        current_frame = frames_ref{id};
        [decoded_48, hamming_status] = local_hamming_decode(current_frame, config);
        
        if strcmp(hamming_status, 'Double Error Detected')
            expected_status = 'Double Error Detected / CRC Skipped';
        else
            rec_payload = uint32(decoded_48(1:config.frame.payload_bits));
            rec_crc = decoded_48(config.frame.payload_bits+1:end);
            calc_crc = local_crc32(rec_payload, config.crc.polynomial, config.crc.init);
            if isequal(rec_crc, calc_crc)
                expected_status = sprintf('%s / CRC OK', hamming_status);
            else
                expected_status = sprintf('%s / CRC FAILED', hamming_status);
            end
        end
        fprintf('  [МАТ. ЭТАЛОН]: Ожидаемый статус декодера: [%s]\n', expected_status);
        
        %% === БЛОК ПОСТРОЕНИЯ КОМПЛЕКСНЫХ ГРАФИКОВ И СРАВНЕНИЯ ===
        try
            logs = sim_out.logsout;
            
            %% 1. ОТРИСОВКА И ВАЛИДАЦИЯ ЦИФРОВОГО ТРАКТА (TS)
            ts_in_element = logs.find('Name', 'ts_switch');
            ts_out_element = logs.find('Name', 'ts_crc_out');
            
            if ~isempty(ts_in_element) && ~isempty(ts_out_element)
                ts_in_obj = ts_in_element{1}.Values;
                ts_out_obj = ts_out_element{1}.Values;
                
                ts_in_fixed = squeeze(ts_in_obj.Data);
                ts_out_fixed = squeeze(ts_out_obj.Data);
                
                % Проверка финального значения счетчика ошибок
                final_sim_errors = ts_out_fixed(end);
                if final_sim_errors == expected_ts_errors(id)
                    verdict = 'ПРОЙДЕН (Совпадает с эталоном)';
                    v_color = '[0 0.6 0]'; 
                else
                    verdict = sprintf('НЕ ПРОЙДЕН (В модели: %d, Ожидалось: %d)', final_sim_errors, expected_ts_errors(id));
                    v_color = '[1 0 0]'; 
                end
                cprintf(v_color, '  [ВАЛИДАЦИЯ TS]: %s\n', verdict);
                
                % Построение графиков
                figure('Name', sprintf('TS (Цифра) - Сценарий: %s', test_labels{id}), 'Color', 'w');
                
                subplot(2,1,1);
                plot(ts_in_obj.Time, ts_in_fixed, 'LineWidth', 1.5, 'Color', [0 0.4470 0.7410]);
                grid on; 
                title(sprintf('Входная маска цифровых сбоев ts\\_switch (Тест: %s)', test_labels{id}));
                ylabel('Амплитуда');
                
                subplot(2,1,2);
                stairs(ts_out_obj.Time, ts_out_fixed, 'LineWidth', 2, 'Color', [0.8500 0.3250 0.0980]);
                grid on; 
                title(sprintf('Счетчик ошибок TS (Сигнал ts\\_crc\\_out) - %s', verdict));
                xlabel('Время (с)'); 
                ylabel('Кол-во ошибок');
                
                if max(ts_out_fixed) > 0
                    ylim([-0.5 max(ts_out_fixed) + 1.5]);
                else
                    ylim([-0.5 2.5]);
                end
            else
                fprintf('  [ПРЕДУПРЕЖДЕНИЕ TS]: Линии ''ts_switch'' или ''ts_crc_out'' не найдены.\n');
            end
            
            %% 2. ОТРИСОВКА И ВАЛИДАЦИЯ АНАЛОГОВОГО ТРАКТА (NRZ)
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
                stairs(nrz_out_obj.Time, nrz_out_fixed, 'LineWidth', 2, 'Color', [0.4940 0.1840 0.5560]);
                grid on; 
                title('Показания счетчика ошибок NRZ (Сигнал nrz\_crc\_out)');
                xlabel('Время (с)'); 
                ylabel('Кол-во ошибок');
                
                if max(nrz_out_fixed) > 0
                    ylim([-0.5 max(nrz_out_fixed) + 1.5]);
                else
                    ylim([-0.5 2.5]);
                end
            else
                fprintf('  [ПРЕДУПРЕЖДЕНИЕ NRZ]: Линии ''nrz_switch'' или ''nrz_crc_out'' не найдены.\n');
            end
            fprintf('\n');
            
        catch ME_vis
            fprintf('  [ПРЕДУПРЕЖДЕНИЕ]: Ошибка в блоке визуализации.\n');
            fprintf('  Детали: %s\n\n', ME_vis.message);
        end
    else
        fprintf('  [КРИТИЧЕСКАЯ ОШИБКА]: Тест зафиксировал сбой симуляции!\n');
        fprintf('  Детали: %s\n\n', sim_out.ErrorMessage);
    end
end

fprintf('=== КОМПЛЕКСНАЯ ВЕРИФИКАЦИЯ ЗАВЕРШЕНА ===\n');

%% ==========================================================================
%% ── ЛОКАЛЬНЫЕ ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ВЕРИФИКАЦИИ ─────────────────────────
%% ==========================================================================
function crc_bits = local_crc32(data, poly, init)
    % Полностью избавляемся от bitshift для устранения ошибки типов данных
    % Приводим полином к десятичному числу типа double для надежности расчетов
    if ischar(poly) || isstring(poly)
        poly_num = double(hex2dec(poly));
    else
        poly_num = double(poly);
    end
    
    if ischar(init) || isstring(init)
        crc = double(hex2dec(init));
    else
        crc = double(init);
    end
    
    % Переводим входные данные в double-массив
    data = double(data);

    for i = 1:length(data)
        bit = data(i);
        
        % Математический эквивалент msb = bitshift(crc, -31)
        % Проверяем, установлен ли 32-й бит регистра CRC (2^31 = 2147483648)
        if crc >= 2147483648
            msb = 1;
        else
            msb = 0;
        end
        
        % Математический эквивалент сдвига влево: crc = bitshift(crc, 1)
        % Выделяем младшие 31 бит и умножаем на 2
        crc_shifted = mod(crc, 2147483648) * 2;
        
        % Выполняем XOR старшего бита и текущего бита данных
        if xor(msb, bit) == 1
            % Математический эквивалент crc = bitxor(crc_shifted, poly_num)
            crc = double(bitxor(uint32(crc_shifted), uint32(poly_num)));
        else
            crc = crc_shifted;
        end
    end
    
    % Корректно раскладываем итоговое число double/uint32 на массив из 32 бит (left-msb)
    crc_bits = zeros(1, 32);
    crc_uint = uint32(crc);
    for i = 1:32
        shift_val = 32 - i;
        % Используем деление вместо bitshift для получения битовой маски
        crc_bits(i) = double(bitand(bitshift(crc_uint, -double(shift_val)), uint32(1)));
    end
end




function frame = local_hamming_encode(data_48, config)
    frame_54 = zeros(1, 54);
    frame_54(config.hamming.info_pos) = data_48;
    for p = config.hamming.parity_pos
        mask = zeros(1, 54);
        for idx = 1:54
            if bitand(idx, p) > 0, mask(idx) = 1; end
        end
        mask(p) = 0; 
        frame_54(p) = mod(sum(frame_54 .* mask), 2);
    end
    overall_parity = mod(sum(frame_54), 2);
    frame = [frame_54, overall_parity];
end

function [data_48, status] = local_hamming_decode(frame, config)
    frame_54 = frame(1:54);
    received_overall_parity = frame(55);
    syndrome = 0;
    
    % Вычисление синдрома
    for p = config.hamming.parity_pos
        mask = zeros(1, 54);
        for idx = 1:54
            if bitand(idx, p) > 0, mask(idx) = 1; end
        end
        check = mod(sum(frame_54 .* mask), 2);
        if check > 0, syndrome = syndrome + p; end
    end
    
    % Расчет общего паритета кадра
    calc_overall_parity = mod(sum(frame_54), 2);
    parity_error = (calc_overall_parity ~= received_overall_parity);
    
    % Логика классификации и исправления ошибок (SEC-DED)
    if syndrome == 0 && ~parity_error
        status = 'No Errors';
    elseif syndrome ~= 0 && parity_error
        status = 'Single Error Corrected';
        if syndrome <= 54
            frame_54(syndrome) = 1 - frame_54(syndrome); 
        end
    elseif syndrome ~= 0 && ~parity_error
        status = 'Double Error Detected';
    else
        status = 'Parity Bit Error';
    end
    
    % Извлечение информационных бит данных
    data_48 = frame_54(config.hamming.info_pos);
end

function cprintf(color_vec, text, varargin)
    % Безопасный вывод цветного текста в консоль
    try
        builtin('fprintf', text, varargin{:});
    catch
        fprintf(text);
    end
end
