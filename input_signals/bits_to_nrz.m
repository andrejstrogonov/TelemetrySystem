function [nrz_dac, nrz_voltage, time_axis] = bits_to_nrz(bit_vector, config)
% BITS_TO_NRZ  Преобразование битового вектора в NRZ-сигнал для AWG.
%
%   [nrz_dac, nrz_voltage, time_axis] = bits_to_nrz(bit_vector)
%   [nrz_dac, nrz_voltage, time_axis] = bits_to_nrz(bit_vector, config)
%
%   Вход:
%     bit_vector  — вектор бит (0/1), обычно 32 элемента
%     config      — структура конфигурации (опционально)
%
%   Выход:
%     nrz_dac     — вектор 14-битных кодов ЦАП (0..16383), 8192 точки
%     nrz_voltage — вектор напряжений (В), для визуализации
%     time_axis   — ось времени (с), для построения графиков

    if nargin < 2 || isempty(config)
        awg_depth     = 8192;
        points_per_bit= 256;
        dac_max       = 16383;
        level_low     = 0;
        level_high    = 16383;
        voltage_low   = 0.0;
        voltage_high  = 3.3;
        sample_rate   = 8192000;
    else
        awg_depth      = config.owon.awg_depth;
        points_per_bit = config.nrz.points_per_bit;
        dac_max        = config.owon.dac_max;
        level_low      = config.nrz.level_low;
        level_high     = config.nrz.level_high;
        voltage_low    = config.nrz.voltage_low;
        voltage_high   = config.nrz.voltage_high;
        sample_rate    = config.nrz.sample_rate;
    end

    n_bits = numel(bit_vector);
    assert(n_bits * points_per_bit <= awg_depth, ...
        'Сигнал (%d точек) превышает глубину AWG (%d)', ...
        n_bits * points_per_bit, awg_depth);

    % Дополняем нулями до полной глубины AWG
    total_points = awg_depth;
    nrz_dac = zeros(1, total_points);

    % Заполняем: каждый бит повторяется points_per_bit раз
    for i = 1:n_bits
        idx_start = (i - 1) * points_per_bit + 1;
        idx_end   = i * points_per_bit;
        if bit_vector(i) == 1
            nrz_dac(idx_start:idx_end) = level_high;
        else
            nrz_dac(idx_start:idx_end) = level_low;
        end
    end

    % Остальные точки — нули (тишина после кадра)

    % Преобразование DAC-кодов в напряжение
    dac_range = level_high - level_low;
    volt_range = voltage_high - voltage_low;
    nrz_voltage = voltage_low + (double(nrz_dac) - level_low) / dac_range * volt_range;

    % Ось времени
    time_axis = (0:total_points-1) / sample_rate;
end
