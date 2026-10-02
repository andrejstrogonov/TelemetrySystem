function run_ci()
project_root = fileparts(fileparts(mfilename('fullpath')));
original_directory = pwd;
restore_directory = onCleanup(@() cd(original_directory));
cd(project_root);
addpath(fullfile(project_root, 'model'));
addpath(fullfile(project_root, 'model', 'ecc'));
addpath(fullfile(project_root, 'input_signals'));

artifacts = fullfile(project_root, 'artifacts', 'ci');
if ~exist(artifacts, 'dir')
    mkdir(artifacts);
end

context = initialize_telemetry_workspace(project_root);
run(fullfile(project_root, 'model', 'ecc', 'build_ecc_memory_subsystem.m'));
build_integrated_telemetry_system(project_root);
verify_matlab_ecc(context);
verify_integrated_simulation(context, artifacts);
snapshot_trace = verify_snapshot_window(context, artifacts);
write_status_json(context, artifacts);
write_signal_plot(context, artifacts, snapshot_trace);
verify_json_with_electron_validator(project_root, artifacts);
verify_rtl_with_questa();
verify_altium_manifest(project_root);
verify_mcu_sources(project_root);

fprintf('CI PASS; artifacts: %s', artifacts);
clear restore_directory;
end

function verify_matlab_ecc(context)
signals = context.test_signals;
config = context.config;
encoded = ecc_hamming_encode(signals.data_48, config);
[decoded, status] = ecc_hamming_decode(encoded, config);
assert(strcmp(status, 'no_error') && isequal(decoded, signals.data_48), ...
    'ECC clean round-trip failed.');

for bit_index = 1:55
    damaged = encoded;
    damaged(bit_index) = 1 - damaged(bit_index);
    [recovered, error_status] = ecc_hamming_decode(damaged, config);
    assert(strcmp(error_status, 'corrected') && isequal(recovered, signals.data_48), ...
        'ECC failed to correct bit %d.', bit_index);
end

damaged = encoded;
damaged([5 12]) = 1 - damaged([5 12]);
[~, error_status] = ecc_hamming_decode(damaged, config);
assert(strcmp(error_status, 'uncorrectable'), 'ECC failed to detect a two-bit error.');
fprintf('PASS MATLAB ECC reference: clean, 55 single-bit, double-bit.');
end

function verify_integrated_simulation(context, artifacts)
model_name = 'sim_new_telemetry_system';
load_system(fullfile('model', [model_name '.slx']));
time = (0:10)';
trigger = false(numel(time), 1);
trigger(6) = true;
sample = ones(numel(time), 1);
sample(6) = 1.4;
reference = ones(numel(time), 1);
payload_crc = repmat(context.test_signals.data_48, numel(time), 1);
error_mode = zeros(numel(time), 1, 'uint8');
error_mode(2) = 1;
error_mode(3) = 2;

inputs = make_external_inputs(trigger, sample, reference, payload_crc, error_mode, time);
simulation_input = Simulink.SimulationInput(model_name);
simulation_input = simulation_input.setExternalInput(inputs);
simulation_input = simulation_input.setModelParameter('StopTime', '10');
simulation_output = sim(simulation_input);
outputs = simulation_output.get('yout');

crc_data = outputs.getElement(1).Values;
ecc_uncorrectable = squeeze(outputs.getElement(8).Values.Data);
snapshot_ready = squeeze(outputs.getElement(11).Values.Data);
ecc_corrected = squeeze(outputs.getElement(15).Values.Data);
assert(any(ecc_corrected ~= 0), 'Integrated model did not report single-bit correction.');
assert(any(ecc_uncorrectable ~= 0), 'Integrated model did not report double-bit error.');

save(fullfile(artifacts, 'integrated_signals.mat'), ...
    'time', 'crc_data', 'ecc_corrected', 'ecc_uncorrectable', 'snapshot_ready');
assignin('base', 'ci_integrated_simulation_output', simulation_output);
fprintf('PASS integrated Simulink: CRC traces and ECC fault scenarios.');
end

function trace = verify_snapshot_window(context, artifacts)
model_name = 'ecc_memory_subsystem';
load_system(fullfile('model', [model_name '.slx']));
time = (0:265)';
trigger = false(numel(time), 1);
trigger(11) = true;
sample = ones(numel(time), 1);
reference = ones(numel(time), 1);
payload_crc = repmat(context.test_signals.data_48, numel(time), 1);
error_mode = zeros(numel(time), 1, 'uint8');

inputs = make_external_inputs(trigger, sample, reference, payload_crc, error_mode, time);
simulation_input = Simulink.SimulationInput(model_name);
simulation_input = simulation_input.setExternalInput(inputs);
simulation_input = simulation_input.setModelParameter('StopTime', '265');
simulation_output = sim(simulation_input);
outputs = simulation_output.get('yout');
ready = outputs.getElement(5).Values;
ready_values = squeeze(ready.Data);
ready_index = find(ready_values ~= 0, 1);
assert(~isempty(ready_index) && ready.Time(ready_index) == 265, ...
    'Expected snapshot_ready at t=265 for a trigger at t=10.');

codeword_data = outputs.getElement(10).Values.Data;
assert(isequal(size(codeword_data), [512 55 266]), ...
    'Expected 512x55 ECC snapshot words over 266 simulation steps.');
final_snapshot = codeword_data(:, :, end);
for word_index = 1:size(final_snapshot, 1)
    [~, status] = turbo_decoder(final_snapshot(word_index, :));
    assert(~strcmp(status, 'uncorrectable'), ...
        'Snapshot ECC word %d is not decodable.', word_index);
end
trace = struct('time', ready.Time, 'ready', ready_values, ...
    'ecc_words', final_snapshot);
save(fullfile(artifacts, 'snapshot_signals.mat'), 'trace');
fprintf('PASS ECC snapshot: 256 pre, event, 255 post; 512x55 words.');
end

function dataset = make_external_inputs(trigger, sample, reference, payload_crc, error_mode, time)
dataset = Simulink.SimulationData.Dataset;
dataset = dataset.addElement(timeseries(trigger, time), 'snapshot_trigger');
dataset = dataset.addElement(timeseries(sample, time), 'sample_value');
dataset = dataset.addElement(timeseries(reference, time), 'reference_level');
dataset = dataset.addElement(timeseries(payload_crc, time), 'payload_crc_in');
dataset = dataset.addElement(timeseries(error_mode, time), 'error_mode');
end

function write_status_json(context, artifacts)
signals = context.test_signals;
config = context.config;
[expected_crc_bits, crc_word] = crc32_compute( ...
    signals.payload, config.crc.polynomial, config.crc.init, config.crc.xor_out);
crc_ok = isequal(double(expected_crc_bits), double(signals.crc_bits));
events = struct('type', 'anomaly_high_deviation', 'timestamp_ms', 6000, ...
    'value', 1.4, 'deviation_percent', 40);

status = struct();
status.timestamp_ms = 10000;
status.temperatures_c = struct('stm32', 25.0, 'fpga_1', 25.0, 'fpga_2', 25.0, 'hotspot', 25.0);
status.power = struct('voltage_v', 12.0, 'status', 'external');
status.fan = struct('pwm_percent', 0, 'pin_fan_pwm', 'PA0', 'pin_exp', 'PA1', 'exp_flag', true);
status.crc = struct('last_block_crc32', sprintf('0x%08X', crc_word), 'ok', crc_ok);
status.ecc = struct('corrected', true, 'uncorrectable', true, ...
    'snapshot_ready', false, 'buffer_full', false);
status.events = {events};
status.thresholds_c = struct('target', 70.0, 'max_safe', 85.0);
status.system = struct('mode', 'alarm', 'uptime_s', 10, 'sequence', 10);

json_path = fullfile(artifacts, 'status.json');
file_id = fopen(json_path, 'w');
if file_id < 0
    error('Unable to create %s.', json_path);
end
cleanup = onCleanup(@() fclose(file_id));
fwrite(file_id, jsonencode(status, 'PrettyPrint', true));
fprintf(file_id, newline);
clear cleanup;
fprintf('Wrote Electron-compatible JSON: %s', json_path);
end

function write_signal_plot(context, artifacts, snapshot_trace)
results = evalin('base', 'ci_integrated_simulation_output');
outputs = results.get('yout');
crc_data = outputs.getElement(1).Values.Data;
ecc_corrected = squeeze(outputs.getElement(15).Values.Data);
ecc_uncorrectable = squeeze(outputs.getElement(8).Values.Data);
time = (0:numel(ecc_corrected) - 1)';

figure_handle = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1100 720]);
subplot(2, 2, 1);
plot(context.test_signals.time_axis{1}(1:1024), context.test_signals.nrz_voltage{1}(1:1024));
title('Owon input waveform');
xlabel('Time (s)');
ylabel('Voltage (V)');
grid on;
subplot(2, 2, 2);
stairs(0:size(crc_data, 3)-1, squeeze(crc_data(1, 1, :)));
title('CRC data output');
xlabel('Sample');
ylabel('Bit');
grid on;
subplot(2, 2, 3);
stairs(time, ecc_corrected, 'LineWidth', 1.4);
hold on;
stairs(time, ecc_uncorrectable, 'LineWidth', 1.4);
title('ECC status');
xlabel('Time (s)');
ylabel('Flag');
legend('corrected', 'uncorrectable', 'Location', 'best');
grid on;
subplot(2, 2, 4);
stairs(snapshot_trace.time, snapshot_trace.ready, 'LineWidth', 1.4);
title('Snapshot ready');
xlabel('Time (s)');
ylabel('Flag');
grid on;
axes_handles = findall(figure_handle, 'Type', 'axes');
for axes_index = 1:numel(axes_handles)
    set(axes_handles(axes_index), 'Color', 'w', 'XColor', 'k', 'YColor', 'k', ...
        'GridColor', [0.75 0.75 0.75], 'GridAlpha', 0.5);
end
text_handles = findall(figure_handle, 'Type', 'text');
set(text_handles, 'Color', 'k');
legend_handle = findall(figure_handle, 'Type', 'legend');
set(legend_handle, 'Color', 'w', 'TextColor', 'k', 'EdgeColor', [0.6 0.6 0.6]);
exportgraphics(figure_handle, fullfile(artifacts, 'signals.png'));
close(figure_handle);
end

function verify_json_with_electron_validator(project_root, artifacts)
validator = fullfile(project_root, 'electron-telemetry', 'scripts', 'validateTelemetryData.js');
json_file = fullfile(artifacts, 'status.json');
command = sprintf('node "%s" --source="%s"', validator, json_file);
[status, output] = system(command);
fprintf('%s', output);
assert(status == 0, 'Electron telemetry schema validation failed.');
end

function verify_rtl_with_questa()
vlog = getenv('QUESTA_VLOG');
if isempty(vlog) && ispc
    candidate = 'C:\altera\25.1std\questa_fse\win64\vlog.exe';
    if exist(candidate, 'file')
        vlog = candidate;
    end
end
if isempty(vlog) && ~ispc
    [~, found] = system('command -v vlog');
    vlog = strtrim(found);
end
if isempty(vlog) || ~exist(vlog, 'file')
    warning('Questa vlog not found; skipping local RTL compile. Set QUESTA_VLOG in CI to require this check.');
    return;
end

library_path = tempname(tempdir);
library_cleanup = onCleanup(@() remove_temporary_directory(library_path));
tool_directory = fileparts(vlog);
if ispc
    vlib = fullfile(tool_directory, 'vlib.exe');
else
    vlib = fullfile(tool_directory, 'vlib');
end
library_argument = strrep(library_path, '\', '/');
if exist(vlib, 'file')
    [library_status, library_output] = system(sprintf('"%s" "%s"', vlib, library_argument));
    fprintf('%s', library_output);
    assert(library_status == 0, 'Unable to create Questa work library.');
end

sources = [ ...
    'ecc-logging/ecc_ring_buffer.v ' ...
    'ecc-logging/anomaly_detector.v ' ...
    'ecc-logging/ecc_logging.v ' ...
    'tests/ecc_ring_buffer_tb.v ' ...
    'tests/anomaly_detector_tb.v'];
command = sprintf('"%s" -work "%s" %s', vlog, library_argument, sources);
[compile_status, compile_output] = system(command);
fprintf('%s', compile_output);
assert(compile_status == 0, 'Questa RTL compilation failed.');

if ispc
    vsim = fullfile(tool_directory, 'vsim.exe');
else
    vsim = fullfile(tool_directory, 'vsim');
end
if exist(vsim, 'file')
    testbenches = {'ecc_ring_buffer_tb', 'anomaly_detector_tb'};
    for test_index = 1:numel(testbenches)
        run_command = sprintf('"%s" -c -lib "%s" %s -do "run -all"', ...
            vsim, library_argument, testbenches{test_index});
        [run_status, run_output] = system(run_command);
        fprintf('%s', run_output);
        assert(run_status == 0 && contains(run_output, 'PASS'), ...
            'Questa testbench failed: %s', testbenches{test_index});
    end
end
clear library_cleanup;
fprintf('PASS FPGA RTL compile and testbenches (Questa).');
end

function verify_altium_manifest(project_root)
bom_path = fullfile(project_root, 'hardware', 'altium', 'BOM.csv');
nets_path = fullfile(project_root, 'hardware', 'altium', 'NETS.csv');
bom = readtable(bom_path, 'TextType', 'string', 'VariableNamingRule', 'preserve');
nets = readtable(nets_path, 'TextType', 'string', 'VariableNamingRule', 'preserve');
assert(height(bom) >= 20, 'Altium BOM is missing selected components.');
assert(numel(unique(bom.Designator)) == height(bom) && ...
    ~any(contains(bom.Designator, "*")), 'Altium BOM has duplicate or wildcard designators.');
assert(any(bom.Designator == "U4") && any(bom.Designator == "U5") && any(bom.Designator == "U6"), ...
    'Altium BOM lacks FPGA/MCU/ADC components.');
assert(any(nets.Net == "1V2_CORE") && any(nets.Net == "3V3_IO") && any(nets.Net == "RS485_A_B"), ...
    'Altium net list is missing a required rail or external link.');
fprintf('PASS Altium manifest: %d BOM entries, %d nets.\n', height(bom), height(nets));
end

function verify_mcu_sources(project_root)
protocol_source = fullfile(project_root, 'mcu', 'stm32g0b1', 'Core', 'Src', 'telemetry_protocol.c');
header_source = fullfile(project_root, 'mcu', 'stm32g0b1', 'Core', 'Inc', 'telemetry_protocol.h');
hal_source = fullfile(project_root, 'mcu', 'stm32g0b1', 'Core', 'Src', 'main.c');
assert(exist(protocol_source, 'file') && exist(header_source, 'file') && exist(hal_source, 'file'), ...
    'STM32 telemetry sources are incomplete.');
fprintf('PASS STM32 sources present; HAL build requires STM32CubeG0.\n');
end

function remove_temporary_directory(directory_path)
if exist(directory_path, 'dir')
    try
        rmdir(directory_path, 's');
    catch
    end
end
end