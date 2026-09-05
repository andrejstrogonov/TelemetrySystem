% Настройка параметров хранения для генерации Си-кода
N = 512; % Rev A ring buffer depth

% 1. Настройка для Path A (Одиночная переменная)
Log_PathA = Simulink.Signal;
Log_PathA.CoderInfo.StorageClass = 'ExportedGlobal'; % Сделает переменную глобальной в Си
Log_PathA.DataType = 'single';

% 2. Настройка для Path B (Массив окна данных)
Snapshot_PathB = Simulink.Signal;
Snapshot_PathB.CoderInfo.StorageClass = 'ExportedGlobal';
Snapshot_PathB.DataType = 'single';
Snapshot_PathB.Dimensions = [N, 1]; % 256 samples before + 256 after event

% 3. Флаг готовности снимка для прерывания или таски в STM32
Snapshot_Ready_Flag = Simulink.Signal;
Snapshot_Ready_Flag.CoderInfo.StorageClass = 'ExportedGlobal';
Snapshot_Ready_Flag.DataType = 'boolean';
