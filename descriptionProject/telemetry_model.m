%% Legacy/HIL модель системы; аппаратный baseline Rev A описан в SYSTEM_ENGINEERING_SPECIFICATION.md
clear; clc; close all;

%% Параметры симуляции
Fs = 1e6;                % частота дискретизации (Гц)
Ts = 1/Fs;               % шаг по времени (с)
Tsim = 90;               % длительность симуляции (с)
N = round(Tsim/Ts);      % количество шагов
t = (0:N-1)' * Ts;       % вектор времени

%% Тепловая модель legacy-профиля (3 узла: GW1NR-9C FPGA1, GW1NR-9C FPGA2, STM32G0B1CBT6)
T_amb = 40;              % температура окружающей среды (°C)
Rth = [25, 25, 35];      % тепловые сопротивления (°C/Вт)
tau = [30, 30, 20];      % постоянные времени нагрева (с)
P_base = [0.3, 0.3, 0.1]; % базовая рассеиваемая мощность (Вт)

% Нагрузочный профиль (ступенчатое увеличение)
load_factor = ones(N,1);
load_factor(round(0.3*N):end) = 1.5;
load_factor(round(0.6*N):end) = 2.0;
P = P_base(:) * load_factor';

T = T_amb * ones(3, N+1); % T(1,:) FPGA1, T(2,:) FPGA2, T(3,:) STM32

%% ПИ‑регулятор и вентилятор (Исправленная версия)
T_target = 70;           % целевая температура (°C)
T_max_safe = 85;         % аварийный порог (°C)
Kp = 0.6;                 % пропорциональный коэффициент
Ki = 0.03;                % интегральный коэффициент
error_int = 0;

% Предвыделение памяти (N берется из вашего прошлого скрипта, например 60000)
pwm_duty = zeros(N, 1);   
pin_exp = zeros(N, 1);     
T = zeros(3, N);          

% Гарантируем, что базовые параметры являются векторами-столбцами (3x1)
tau = tau(:);
Rth = Rth(:);
inv_tau = 1 ./ tau;       

for k = 1:N-1
    % Принудительно извлекаем как векторы-столбцы (3x1)
    Tk = T(:, k);
    Pk = P(:, k);
    
    % 1. Нагрев без учёта обдува
    dT = (Pk .* Rth - (Tk - T_amb)) .* inv_tau;
    Tk_next = Tk + dT * Ts;

    % 2. Учёт обдува
    pwm_prev = pwm_duty(max(k-1, 1)); 
    
    % FIX: Явно используем . / для поэлементного деления
    Rth_eff = Rth ./ (1 + 2 * pwm_prev); 
    
    % FIX: Все операции строго поэлементные (.*)
    dT_cool = (Pk .* Rth_eff - (Tk_next - T_amb)) .* inv_tau;
    
    % Теперь размер строго 3х1 с обеих сторон
    T(:, k+1) = Tk_next + (dT_cool * Ts);

    % Находим хотспот для ПИ-регулятора
    T_current = max(T(:, k+1)); 

    % 3. ПИ‑регулятор
    error = T_current - T_target;
    error_int = error_int + error * Ts;
    pwm_raw = Kp * error + Ki * error_int;
    
    if pwm_raw > 1
        pwm_clamped = 1;
    elseif pwm_raw < 0
        pwm_clamped = 0;
    else
        pwm_clamped = pwm_raw;
    end
    
    pwm_duty(k) = pwm_clamped;
    pin_exp(k) = double(T_current > T_max_safe);
end

% Заполнение последней точки для ШИМ и флага
pwm_duty(N) = pwm_duty(N-1); 
pin_exp(N) = double(max(T(:, N)) > T_max_safe);

%% Фильтрация сигнала и детектирование аномалий (FPGA2) - Оптимизированный
% Входной сигнал: синусоида + ступенчатые выбросы
f_sig = 5;                % частота полезного сигнала (Гц)
A_sig = 1;                % амплитуда
signal_raw = A_sig * sin(2*pi*f_sig*t);

% ОПТИМИЗАЦИЯ: Векторизованное добавление ступенчатых аномалий без циклов
% Создаем один комбинированный вектор смещения и применяем его за один шаг
anomaly_shift = zeros(size(signal_raw));
anomaly_shift(round(0.4*N):end) = anomaly_shift(round(0.4*N):end) + 0.5*A_sig;
anomaly_shift(round(0.75*N):end) = anomaly_shift(round(0.75*N):end) + 0.5*A_sig;
signal_raw = signal_raw + anomaly_shift;

% FIR‑фильтр (эмуляция FPGA2)
N_taps = 31;             % нечётное число коэффициентов
fc = 10;                 % частота среза (Гц)
fir_coeffs = fir1(N_taps-1, 2*fc/Fs);
signal_filtered = filter(fir_coeffs, 1, signal_raw);

% Скользящее среднее для детектирования аномалий
window_size = round(0.1*Fs); % 100 мс
signal_smooth = movmean(signal_filtered, window_size, 'Endpoints','shrink');

% ОПТИМИЗАЦИЯ: Избегаем промежуточных переменных, считаем флаг напрямую одной операцией.
% Также используем abs(signal_smooth), чтобы избежать ложных срабатываний, когда синусоида уходит в минус.
anomaly_flag = double(abs(signal_filtered - signal_smooth) > (0.3 * abs(signal_smooth)));


%% CRC32‑контроль целостности (эмуляция FPGA1) и Dual-Path логирование
% Разбиваем поток данных на блоки по M отсчётов
M = 128;
N_blocks = floor(N/M);
crc_ok = true(N_blocks,1); % в симуляции считаем CRC всегда верным
sequence_id = 1:N_blocks;

% FIX: Предрасчет глобального вектора отклонений один раз перед циклом (для скорости)
deviation = abs(signal_filtered - signal_smooth);

% Dual‑Path логирование
% RAM: кольцевой буфер (последние N_ram записей)
N_ram = 2000;
ram_buffer = zeros(N_ram, 4); % [timestamp, hotspot, pwm, exp_flag]
ram_head = 1;

% QSPI: только аварии и большие отклонения (>30%)
% FIX: Намного быстрее сделать предвыделение под максимальный размер (N_blocks),
% а в конце просто отсечь пустые строки. Это убирает предупреждение о динамическом размере.
qspi_log_buffer = zeros(N_blocks, 6); 
qspi_counter = 0; % Счетчик фактически добавленных записей аварий

for b = 1:N_blocks
    idx_start = (b-1)*M + 1;
    idx_end = b*M;
    
    % hotspot и статус текущего блока
    T_hot_block = max(max(T(:, idx_start:idx_end)));
    pwm_block = mean(pwm_duty(idx_start:idx_end));
    exp_block = any(pin_exp(idx_start:idx_end));
    
    % Записываем в RAM (кольцевой буфер)
    ram_row = [idx_end*Ts, T_hot_block, pwm_block, double(exp_block)];
    ram_buffer(ram_head, :) = ram_row;
    ram_head = mod(ram_head, N_ram) + 1;
    
    % Если авария или аномалия — пишем в QSPI логгер
    if exp_block || any(anomaly_flag(idx_start:idx_end))
        % Формируем расширенную строку лога с аномалиями
        qspi_entry = [idx_end*Ts, T_hot_block, pwm_block, double(exp_block), ...
                      sum(anomaly_flag(idx_start:idx_end)), max(deviation(idx_start:idx_end))];
        
        % Быстрая запись по индексу вместо медленной склейки
        qspi_counter = qspi_counter + 1;
        qspi_log_buffer(qspi_counter, :) = qspi_entry;
    end
end

% FIX: Обрезаем неиспользованный хвост буфера QSPI до фактического размера событий
qspi_log = qspi_log_buffer(1:qspi_counter, :);

%% Отчёт и графики (Исправленная версия)
fprintf('Max FPGA1: %.1f °C\n', max(T(1,:)));
fprintf('Max FPGA2: %.1f °C\n', max(T(2,:)));
fprintf('Max STM32: %.1f °C\n', max(T(3,:)));
fprintf('Avg PWM: %.1f %%\n', mean(pwm_duty)*100);
fprintf('Time above T_max_safe: %.1f s\n', sum(max(T,[],1) > T_max_safe)*Ts);
fprintf('Number of detected anomalies (>30%%): %d\n', sum(anomaly_flag));

% Предотвращение ошибки, если qspi_log не был инициализирован ранее
if exist('qspi_log', 'var')
    fprintf('QSPI log entries (аварии/аномалии): %d\n', size(qspi_log,1));
else
    fprintf('QSPI log entries (аварии/аномалии): 0 (Лог пуст)\n');
end

figure('Color','w');
subplot(3,1,1); plot(t, T(1,:), 'r', t, T(2,:), 'm', t, T(3,:), 'g'); hold on;
plot([0 Tsim], [T_target T_target], 'k--'); plot([0 Tsim], [T_max_safe T_max_safe], 'r--');
ylabel('Temp, °C'); title('Temperatures FPGA1, FPGA2, STM32'); grid on; legend('FPGA1','FPGA2','STM32','Target','MaxSafe');

subplot(3,1,2); plot(t, pwm_duty*100, 'b'); ylabel('%'); title('PWM Fan'); grid on;

subplot(3,1,3); plot(t, pin_exp, 'k--'); ylabel('Flag'); title('PIN_EXP (Alarm)'); grid on; xlabel('Time, s');
sgtitle('Thermal model: 2x FPGA + STM32 + PWM control');

% FIX: Восстанавливаем переменные для графика (расчет занимает доли секунды вне цикла)
deviation = abs(signal_filtered - signal_smooth);
threshold_dev = 0.3 * abs(signal_smooth); % Используем abs для корректного порога синусоиды

figure('Color','w');
subplot(2,1,1); plot(t, signal_raw, 'k', t, signal_filtered, 'b');
ylabel('Signal'); title('Raw vs Filtered (FPGA2 FIR)'); grid on; legend('Raw','Filtered');
subplot(2,1,2); plot(t, deviation, 'r', t, threshold_dev, 'g--');
ylabel('Deviation'); title('Anomaly detection (>30% threshold)'); grid on; legend('Deviation','Threshold');
xlabel('Time, s');


%% JSON‑шаблон (пример для последнего момента)
T_hot = max(T(:,end));
pwm_pct = round(pwm_duty(end)*100); % JSON ожидает целое число %d для pwm_percent

% Определяем строковый флаг аварии
if T_hot > T_max_safe
    is_alarm_str = 'true';
else
    is_alarm_str = 'false';
end

% Находим последний индекс, где была обнаружена аномалия
last_anomaly_idx = find(anomaly_flag, 1, 'last');

if ~isempty(last_anomaly_idx)
    % Если аномалии были, берем данные из последней точки
    event_timestamp = round(t(last_anomaly_idx) * 1000); % перевод в мс
    event_value = signal_filtered(last_anomaly_idx);
    event_dev = deviation(last_anomaly_idx) * 100;       % в процентах
else
    % Если аномалий не было, пишем нули/дефолты
    event_timestamp = 0;
    event_value = 0.0;
    event_dev = 0.0;
end

% Генерация JSON строки с привязкой к реальным переменным скрипта
json_status = sprintf([...
    '{\n',...
    '  "timestamp_ms": %d,\n',...
    '  "temperatures_c": {\n',...
    '    "stm32": %.1f, "fpga_1": %.1f, "fpga_2": %.1f, "hotspot": %.1f\n',...
    '  },\n',...
    '  "power": {\n',...
    '    "voltage_v": 4.98, "status": "ok"\n',...
    '  },\n',...
    '  "fan": {\n',...
    '    "pwm_percent": %d, "pin_fan_pwm": "PA0", "pin_exp": "PA1", "exp_flag": "%s"\n',...
    '  },\n',...
    '  "crc": {\n',...
    '    "last_block_crc32": "0x9A3F2B1C", "ok": true\n',...
    '  },\n',...
    '  "events": [\n',...
    '    {\n',...
    '      "type": "anomaly_high_deviation",\n',...
    '      "timestamp_ms": %d,\n',...
    '      "value": %.2f,\n',...
    '      "deviation_percent": %.1f\n',...
    '    }\n',...
    '  ],\n',...
    '  "thresholds_c": {"target": %.1f, "max_safe": %.1f},\n',...
    '  "system": {"mode": "normal", "uptime_s": %d}\n',...
    '}'], ...
    round(t(end)*1000), ...      % timestamp_ms (Текущее время симуляции в мс)
    T(3,end), ...                % stm32 температура
    T(1,end), ...                % fpga_1 температура
    T(2,end), ...                % fpga_2 температура
    T_hot, ...                   % hotspot
    pwm_pct, ...                 % pwm_percent
    is_alarm_str, ...            % exp_flag ("true" или "false")
    event_timestamp, ...         % event: timestamp_ms
    event_value, ...             % event: value
    event_dev, ...               % event: deviation_percent
    T_target, ...                % target threshold
    T_max_safe, ...              % max_safe threshold
    round(t(end)));              % uptime_s (Время симуляции в секундах)

disp(json_status);


%% Экспорт данных для САПР/отчётности (Максимально быстрое сохранение)

% Предотвращаем падение скрипта, если логи не были созданы в процессе симуляции
if ~exist('qspi_log', 'var'), qspi_log = []; end
if ~exist('ram_buffer', 'var'), ram_buffer = []; end

% ОПТИМИЗАЦИЯ СКОРОСТИ И РАЗМЕРА: Прореживание данных (Downsampling)
% Для графиков и Altium частоты 1000 Гц не нужны. Возьмем каждую 10-ю точку (100 Гц).
% Это уменьшит объем данных и время сохранения в 10 раз!
decim = 10; % Коэффициент прореживания (измените на 1, если нужны абсолютно все точки)

t_save               = t(1:decim:end);
T_save               = T(:, 1:decim:end);
pwm_duty_save        = pwm_duty(1:decim:end);
pin_exp_save         = pin_exp(1:decim:end);
signal_raw_save      = signal_raw(1:decim:end);
signal_filtered_save = signal_filtered(1:decim:end);
anomaly_flag_save    = anomaly_flag(1:decim:end);

% ОПТИМИЗАЦИЯ MATLAB: Отключаем сжатие данных (сохраняет мгновенно)
% Если ваша версия старая и выдает ошибку на '-nocompression', просто удалите этот аргумент.
save('system_model_data.mat', ...
     't_save', 'T_save', 'pwm_duty_save', 'pin_exp_save', ...
     'signal_raw_save', 'signal_filtered_save', 'anomaly_flag_save', ...
     'qspi_log', 'ram_buffer', '-v7.3', '-nocompression');

fprintf('Данные мгновенно сохранены в system_model_data.mat (без сжатия, прореживание 1:%d).\n', decim);
