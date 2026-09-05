%% owon_hds242s_config.m
%  Конфигурация Owon HDS242S: AWG, NRZ, CRC, Hamming, SCPI
%  Загружать первым перед всеми остальными скриптами.
%  Версия: 2026-09-02

%% ── Параметры прибора HDS242S ──
config.owon.model          = 'HDS242S';
config.owon.awg_depth      = 8192;       % точек на осциллограмму
config.owon.dac_bits      = 14;         % разрядность ЦАП
config.owon.dac_max       = 2^14 - 1;    % 16383
config.owon.impedance     = 'HIGH';      % High-Z выход
config.owon.usb_vid       = '0483';      % ST Microelectronics VID
config.owon.usb_pid       = '7523';      % USB-CDC PID (типовой)
config.owon.scpi_terminator = '\n';      % терминатор SCPI-команд
config.owon.timeout       = 2;           % таймаут чтения, сек

% Доступные встроенные формы сигналов HDS242S
config.owon.functions = { ...
    'Sine', 'SQUare', 'RAMP', 'PULSe', ...
    'TRIangle', 'SINC', 'BESSEL', 'StairUp'};

%% ── Параметры NRZ-кодирования ──
config.nrz.frame_length   = 55;          % 48 data + 6 Hamming + overall parity
config.nrz.points_per_bit = 128;          % 55*128 = 7040 <= 8192
config.nrz.level_low      = 0;            % логический 0 → код ЦАП
config.nrz.level_high     = 16383;        % логический 1 → код ЦАП
config.nrz.voltage_low    = 0.0;          % вольт
config.nrz.voltage_high   = 3.3;          % вольт
config.nrz.voltage_offset = 1.65;         % смещение, В
config.nrz.bitrate        = 32000;        % бит/с (32 кбит/с)
config.nrz.frame_rate     = config.nrz.bitrate / config.nrz.frame_length;
config.nrz.sample_rate    = 4096000;      % 128 samples/bit at 32 kbit/s

%% ── Структура кадра Rev A (55 бит) ──
config.frame.payload_bits  = 16;          % биты  1..16
config.frame.crc_bits      = 32;          % биты 17..48, CRC-32/MPEG-2
config.frame.data_bits     = 48;          % payload + CRC
config.frame.hamming_bits  = 6;           % parity positions 1,2,4,8,16,32
config.frame.parity_bit    = 1;           % overall parity
config.frame.reserved_bits = 0;
config.frame.total         = 55;          % 54-bit Hamming word + overall parity

%% ── Параметры CRC-32/MPEG-2 ──
config.crc.polynomial      = uint32(hex2dec('04C11DB7'));
config.crc.init            = uint32(hex2dec('FFFFFFFF'));
config.crc.xor_out         = uint32(0);
config.crc.reflect_in      = false;
config.crc.reflect_out     = false;
config.crc.width           = 32;

%% ── Параметры Hamming SEC-DED ──
config.hamming.code_length  = 54;          % длина слова Хэмминга
config.hamming.info_length  = 48;          % информационных позиций
config.hamming.parity_length= 6;           % проверочных позиций
config.hamming.parity_pos   = [1, 2, 4, 8, 16, 32];
config.hamming.info_pos     = setdiff(1:54, config.hamming.parity_pos);
config.hamming.used_info    = 48;
config.hamming.total_length = 55;

%% ── SCPI-шаблоны для HDS242S ──
config.scpi.templates.clock = { ...
    ':FUNCtion SQUare', ...
    ':FUNCtion:FREQuency 16000', ...   % 32 кбит/с / 2 = 16 кГц
    ':FUNCtion:AMPLitude 3.3', ...    % Vpp
    ':FUNCtion:OFFSet 1.65', ...      % смещение
    ':FUNCtion:LOAD OFF', ...         % High-Z
    ':CHANnel ON'};

config.scpi.templates.burst = { ...
    ':FUNCtion PULSe', ...
    ':FUNCtion:FREQuency 1000', ...   % 1 кГц
    ':FUNCtion:AMPLitude 3.3', ...
    ':FUNCtion:OFFSet 1.65', ...
    ':FUNCtion:PULSe:DTYCycle 25.0', ...
    ':FUNCtion:LOAD OFF', ...
    ':CHANnel ON'};

config.scpi.templates.calib = { ...
    ':FUNCtion StairUp', ...
    ':FUNCtion:FREQuency 100', ...
    ':FUNCtion:AMPLitude 3.3', ...
    ':FUNCtion:OFFSet 1.65', ...
    ':FUNCtion:LOAD OFF', ...
    ':CHANnel ON'};

%% ── Параметры тестовых ошибок ──
config.test.single_bit_pos  = 7;          % позиция одиночной ошибки
config.test.double_bit_pos   = [5, 12];    % позиции двойной ошибки
config.test.burst_start      = 3;          % начало пакетной ошибки
config.test.burst_length     = 8;          % длина пакета (бит)
config.test.payload_seed     = 42;         % seed для randi (воспроизводимость)

%% ── Папки для вывода ──
config.paths.output_dir  = 'owon_output';
config.paths.csv_dir     = 'owon_output/csv';
config.paths.scpi_dir    = 'owon_output/scpi';
config.paths.mat_file    = 'owon_output/owon_test_signals.mat';
config.paths.plot_file   = 'owon_output/owon_test_signals_plot.png';
config.paths.simulink_dir = 'owon_output/simulink';

%% ── Сохранить конфиг в Workspace ──
assignin('base', 'config', config);

fprintf('[CONFIG] Owon HDS242S конфигурация загружена.\n');
fprintf('  AWG: %d точек, %d бит, %d точек/бит\n', ...
    config.owon.awg_depth, config.owon.dac_bits, config.nrz.points_per_bit);
fprintf('  Кадр: %d бит (payload=%d, CRC=%d, Hamming=%d, parity=%d)\n', ...
    config.frame.total, config.frame.payload_bits, config.frame.crc_bits, ...
    config.frame.hamming_bits, config.frame.parity_bit);
fprintf('  CRC-32/MPEG-2: poly=0x%08X, init=0x%08X\n', config.crc.polynomial, config.crc.init);
fprintf('  Hamming: (%d,%d) SEC-DED\n', ...
    config.hamming.code_length, config.hamming.info_length);
