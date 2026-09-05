function test_dimensions(polyCoeffs, initState, finalXor)
    % TEST_DIMENSIONS  Проверка CRC-32/MPEG-2 параметров.

    if nargin == 0
        dimension = 32;
        hexPoly = '04C11DB7';
        polyCoeffs = [1, de2bi(hex2dec(hexPoly), dimension, 'left-msb')];
        initState = ones(1, dimension);
        finalXor = zeros(1, dimension);
    end

    % 2. Проверка типов (должны быть double)
    if ~isa(polyCoeffs, 'double') || ~isa(initState, 'double') || ~isa(finalXor, 'double')
        error('Все переменные должны быть типа double.');
    end

    % 3. Проверка размерностей
    expectedPolyLen = 33;   % степень полинома + 1
    expectedStateLen = 32;  % степень полинома

    if length(polyCoeffs) ~= expectedPolyLen
        error('Ошибка: polyCoeffs имеет длину %d, а должна быть %d.', ...
            length(polyCoeffs), expectedPolyLen);
    end

    if length(initState) ~= expectedStateLen
        error('Ошибка: initState имеет длину %d, а должна быть %d.', ...
            length(initState), expectedStateLen);
    end

    if length(finalXor) ~= expectedStateLen
        error('Ошибка: finalXor имеет длину %d, а должна быть %d.', ...
            length(finalXor), expectedStateLen);
    end

    % 4. Проверка содержимого (бинарность)
    if any(polyCoeffs ~= 0 & polyCoeffs ~= 1)
        error('polyCoeffs должен содержать только 0 и 1.');
    end

    if any(initState ~= 1) || any(finalXor ~= 0)
        error('Для CRC-32/MPEG-2 initState должен быть 32 единицы, finalXor - нули.');
    end

    % 5. Успех
    fprintf('Проверка пройдена:\n');
    fprintf('  polyCoeffs: длина %d\n', length(polyCoeffs));
    fprintf('  initState:  длина %d\n', length(initState));
    fprintf('  finalXor:   длина %d\n', length(finalXor));
    fprintf('  Все переменные корректны.\n');
end
