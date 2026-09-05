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