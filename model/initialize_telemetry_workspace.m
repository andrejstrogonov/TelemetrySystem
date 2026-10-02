function context = initialize_telemetry_workspace(project_root)
if nargin == 0 || isempty(project_root)
    project_root = fileparts(fileparts(mfilename('fullpath')));
end

signal_file = fullfile(project_root, 'owon_output', 'owon_test_signals.mat');
loaded = load(signal_file, 'test_signals');
test_signals = loaded.test_signals;
config = test_signals.config;

polynomial = uint32(hex2dec('04C11DB7'));
polynomial_bits = zeros(1, 32);
for bit_index = 1:32
    polynomial_bits(bit_index) = double(bitget(polynomial, 33 - bit_index));
end
polyCoeffs = [1 polynomial_bits];
initState = 1;
finalXor = ones(1, 32);
bus_elements(1) = Simulink.BusElement;
bus_elements(1).Name = 'signal1';
bus_elements(1).DataType = 'boolean';
bus_elements(2) = Simulink.BusElement;
bus_elements(2).Name = 'signal2';
bus_elements(2).DataType = 'boolean';
CRCStatusBus = Simulink.Bus;
CRCStatusBus.Elements = bus_elements;

names = {'ideal', 'single', 'double', 'burst'};
for signal_index = 1:numel(names)
    name = names{signal_index};
    frame = test_signals.(['frame_' name]);
    bit_time = (0:numel(frame) - 1)';
    assignin('base', ['ts_' name], timeseries(frame(:), bit_time));
    assignin('base', ['nrz_' name], timeseries( ...
        test_signals.nrz_voltage{signal_index}(:), ...
        test_signals.time_axis{signal_index}(:)));
end

assignin('base', 'config', config);
assignin('base', 'test_signals', test_signals);
assignin('base', 'polyCoeffs', polyCoeffs);
assignin('base', 'initState', initState);
assignin('base', 'finalXor', finalXor);
assignin('base', 'CRCStatusBus', CRCStatusBus);

context = struct( ...
    'project_root', project_root, ...
    'config', config, ...
    'test_signals', test_signals, ...
    'polyCoeffs', polyCoeffs, ...
    'initState', initState, ...
    'finalXor', finalXor, ...
    'CRCStatusBus', CRCStatusBus);
end