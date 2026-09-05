% Параметры дискретизации и частот
Fs = 100e3;           % Rev A: MCP3201 sampling rate, 100 kSPS
Fpass = 20e3;         % Rev A passband: 20 kHz
Fstop = 40e3;         % Rev A stopband: 40 kHz
Apass = 0.1;          % Пульсации в полосе пропускания (дБ)
Astop = 60;           % Подавление в полосе задерживания (дБ)

% 1. Расчет фильтра (Equiripple КИХ-фильтр, аналог firpm)
lpFilter = designfilt('lowpassfir', ...
    'PassbandFrequency', Fpass, ...
    'StopbandFrequency', Fstop, ...
    'PassbandRipple', Apass, ...
    'StopbandAttenuation', Astop, ...
    'SampleRate', Fs);

% 2. Извлечение коэффициентов для Simulink
b_coeff = lpFilter.Coefficients;
b_coeff = fi(b_coeff, 1, 16, 15); 
% 3. Анализ характеристик фильтра (АЧХ, ФЧХ, Групповая задержка)
fvtool(lpFilter);  % В предыдущем шаге было сделано так, как исправить?

% 1. Находим путь к блоку фильтра в вашей модели
blk = 'fir_filter/Discrete FIR Filter';

% 2. Принудительно выставляем фиксированную точку для ВСЕХ параметров
set_param(blk, 'CoefDataTypeStr', 'fixdt(1,16,15)');
set_param(blk, 'ProductDataTypeStr', 'fixdt(1,32,30)');
set_param(blk, 'AccumDataTypeStr', 'fixdt(1,34,30)');
set_param(blk, 'OutputDataTypeStr', 'fixdt(1,16,15)');

% 3. Фиксируем типы для внутренних состояний (Регистров памяти фильтра)
set_param(blk, 'StateDataTypeStr', 'fixdt(1,16,15)');

% 4. Принудительно убираем double из начальных условий (Initial States)
set_param(blk, 'InitialStates', 'fi(0, 1, 16, 15)');

% 5. Обновляем схему
set_param(bdroot, 'SimulationCommand', 'update');
disp('Все параметры фильтра успешно переведены в Fixed-Point!');

