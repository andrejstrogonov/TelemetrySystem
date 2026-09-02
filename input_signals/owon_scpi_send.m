function [response, port_name] = owon_scpi_send(commands, varargin)
% OWON_SCPI_SEND  Связь с HDS242S по USB через serialport.
%
%   response = owon_scpi_send(commands)           % авто-поиск COM-порта
%   response = owon_scpi_send(commands, 'Port', 'COM5')
%   response = owon_scpi_send(commands, 'Timeout', 3)
%   response = owon_scpi_send(commands, 'DryRun', true)
%   [response, port_name] = owon_scpi_send(...)
%
%   Вход:
%     commands — строка или cell-массив строк SCPI-команд
%   Пары параметр/значение:
%     'Port'    — имя COM-порта ('COM5' и т.п.); если не задан — автопоиск
%     'BaudRate'— скорость (по умолч. 115200)
%     'Timeout' — таймаут чтения, сек (по умолч. 2)
%     'DryRun'  — true → только печать команд, без подключения (тест)
%
%   Выход:
%     response  — cell-массив ответов прибора (пустой, если нет ответа)
%     port_name — имя найденного COM-порта

    % Разбор параметров
    p = inputParser;
    p.addParameter('Port', '', @ischar);
    p.addParameter('BaudRate', 115200, @isnumeric);
    p.addParameter('Timeout', 2, @isnumeric);
    p.addParameter('DryRun', false, @islogical);
    p.parse(varargin{:});
    opts = p.Results;

    % Нормализация команд в cell-массив
    if ischar(commands) || isstring(commands)
        commands = cellstr(commands);
    end

    response = {};

    % ── Режим DryRun: только печать ──
    if opts.DryRun
        fprintf('[DRY-RUN] SCPI команды (%d):\n', numel(commands));
        for i = 1:numel(commands)
            fprintf('  → %s\n', commands{i});
        end
        port_name = '(dry-run)';
        return;
    end

    % ── Поиск COM-порта ──
    port_name = opts.Port;
    if isempty(port_name)
        port_name = find_owon_port();
    end

    if isempty(port_name)
        error('OWON:NoPort', ...
            ['HDS242S не найден. Проверьте USB-подключение.\n', ...
             'Доступные порты: %s'], strjoin(string(serialportlist), ', '));
    end

    fprintf('[SCPI] Подключение к %s @ %d baud...\n', port_name, opts.BaudRate);

    % ── Открытие порта ──
    device = serialport(port_name, opts.BaudRate, 'Timeout', opts.Timeout);
    configureTerminator(device, 'CR/LF');

    cleanup = onCleanup(@() safe_delete(device));

    try
        % Очистка буферов
        flush(device);

        for i = 1:numel(commands)
            cmd = commands{i};

            % Запрос (заканчивается на ?) → чтение ответа
            if endsWith(strtrim(cmd), '?')
                write(device, [cmd, char(10)], 'char');
                pause(0.05);
                try
                    resp = readline(device);
                    response{end+1} = resp;
                    fprintf('  → %s → %s\n', cmd, strtrim(resp));
                catch
                    response{end+1} = '(timeout)';
                    fprintf('  → %s → (timeout)\n', cmd);
                end
            else
                % Команда — только запись
                write(device, [cmd, char(10)], 'char');
                fprintf('  → %s\n', cmd);
            end

            % Небольшая пауза между командами
            pause(0.02);
        end

        fprintf('[SCPI] Готово (%d команд отправлено).\n', numel(commands));

    catch ME
        fprintf('[SCPI] Ошибка: %s\n', ME.message);
        rethrow(ME);
    end
end

%% ── Автопоиск COM-порта Owon ──
function port = find_owon_port()
    ports = serialportlist();
    port = '';

    if isempty(ports)
        fprintf('[SCPI] COM-порты не найдены.\n');
        return;
    end

    fprintf('[SCPI] Поиск HDS242S среди портов: %s\n', strjoin(string(ports), ', '));

    for i = 1:numel(ports)
        try
            dev = serialport(ports{i}, 115200, 'Timeout', 1);
            configureTerminator(dev, 'CR/LF');
            flush(dev);

            % Запрос идентификации
            write(dev, '*IDN?\n', 'char');
            pause(0.15);
            resp = readline(dev);
            delete(dev);

            if contains(resp, 'OWON') || contains(resp, 'HDS')
                port = ports{i};
                fprintf('[SCPI] HDS242S найден на %s: %s\n', port, strtrim(resp));
                return;
            end
        catch
            % Порт не отвечает — пропускаем
            try
                delete(dev);
            catch
            end
        end
    end

    % Если авто-IDN не сработал, возвращаем последний доступный
    if isempty(port) && ~isempty(ports)
        port = ports{end};
        fprintf('[SCPI] Авто-IDN не сработал, используется %s\n', port);
    end
end

function safe_delete(dev)
    try
        delete(dev);
    catch
    end
end
