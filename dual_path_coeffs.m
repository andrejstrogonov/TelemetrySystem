% Настройка параметров хранения для генерации Си-кода
N = 50; % Должно совпадать с length_N внутри функции

% 1. Настройка для Path A (Одиночная переменная)
Log_PathA = Simulink.Signal;
Log_PathA.CoderInfo.StorageClass = 'ExportedGlobal'; % Сделает переменную глобальной в Си
Log_PathA.DataType = 'single';

% 2. Настройка для Path B (Массив окна данных)
Snapshot_PathB = Simulink.Signal;
Snapshot_PathB.CoderInfo.StorageClass = 'ExportedGlobal';
Snapshot_PathB.DataType = 'single';
Snapshot_PathB.Dimensions = [N*2, 1]; % Четко задаем размер массива для компилятора Keil/IAR/GCC

% 3. Флаг готовности снимка для прерывания или таски в STM32
Snapshot_Ready_Flag = Simulink.Signal;
Snapshot_Ready_Flag.CoderInfo.StorageClass = 'ExportedGlobal';
Snapshot_Ready_Flag.DataType = 'boolean';
