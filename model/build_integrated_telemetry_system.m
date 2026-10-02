function model_path = build_integrated_telemetry_system(project_root)
if nargin == 0 || isempty(project_root)
    project_root = fileparts(fileparts(mfilename('fullpath')));
end

initialize_telemetry_workspace(project_root);
addpath(fullfile(project_root, 'model'));
addpath(fullfile(project_root, 'model', 'ecc'));

main_model_name = 'main_signal_system';
main_model_path = fullfile(project_root, 'model', [main_model_name '.slx']);
load_system(main_model_path);
bus_elements(1) = Simulink.BusElement;
bus_elements(1).Name = 'signal1';
bus_elements(1).DataType = 'boolean';
bus_elements(2) = Simulink.BusElement;
bus_elements(2).Name = 'signal2';
bus_elements(2).DataType = 'boolean';
crc_status_bus = Simulink.Bus;
crc_status_bus.Elements = bus_elements;
assignin('base', 'CRCStatusBus', crc_status_bus);
set_param([main_model_name '/validEndOut'], 'OutDataTypeStr', 'Bus: CRCStatusBus');
set_param([main_model_name '/validEndOut_nrz'], 'OutDataTypeStr', 'Bus: CRCStatusBus');
set_param(main_model_name, 'SimulationCommand', 'update');
save_system(main_model_name, main_model_path);
close_system(main_model_name, 0);

model_name = 'sim_new_telemetry_system';
model_path = fullfile(project_root, 'model', [model_name '.slx']);

if bdIsLoaded(model_name)
    close_system(model_name, 0);
end
load_system(model_path);

lines = find_system(model_name, 'FindAll', 'on', 'SearchDepth', 1, 'Type', 'line');
for line_index = 1:numel(lines)
    try
        delete_line(lines(line_index));
    catch
    end
end

blocks = find_system(model_name, 'SearchDepth', 1, 'Type', 'Block');
for block_index = 1:numel(blocks)
    if ~strcmp(blocks{block_index}, model_name)
        delete_block(blocks{block_index});
    end
end

add_block('simulink/Ports & Subsystems/Model', [model_name '/Main_CRC'], ...
    'ModelNameDialog', 'main_signal_system', 'Position', [260 80 430 210]);
add_block('simulink/Ports & Subsystems/Model', [model_name '/ECC_Memory'], ...
    'ModelNameDialog', 'ecc_memory_subsystem', 'Position', [590 80 790 270]);

input_specs = { ...
    'snapshot_trigger', 'boolean', '1', [30 250 60 270]; ...
    'sample_value', 'double', '1', [30 295 60 315]; ...
    'reference_level', 'double', '1', [30 340 60 360]; ...
    'payload_crc_in', 'double', '48', [30 385 60 405]; ...
    'error_mode', 'uint8', '1', [30 430 60 450]};
for input_index = 1:size(input_specs, 1)
    input_path = [model_name '/' input_specs{input_index, 1}];
    add_block('simulink/Ports & Subsystems/In1', input_path, ...
        'Position', input_specs{input_index, 4});
    set_param(input_path, 'OutDataTypeStr', input_specs{input_index, 2}, ...
        'PortDimensions', input_specs{input_index, 3}, ...
        'Port', num2str(input_index));
end

main_outputs = { ...
    'crc_data', 1; ...
    'crc_start', 2; ...
    'crc_status_bus', 3; ...
    'nrz_data', 4; ...
    'nrz_start', 5; ...
    'nrz_status_bus', 6};
for output_index = 1:size(main_outputs, 1)
    output_name = main_outputs{output_index, 1};
    output_port = main_outputs{output_index, 2};
    position = [1000 70 + (output_index - 1) * 42 1030 90 + (output_index - 1) * 42];
    add_model_output(model_name, 'Main_CRC', output_port, output_name, position);
end

ecc_outputs = { ...
    'ecc_data', 1; ...
    'ecc_uncorrectable', 2; ...
    'pathA', 3; ...
    'pathB', 4; ...
    'snapshot_ready', 5; ...
    'system_state', 6; ...
    'write_enable', 7; ...
    'error_alarm', 8; ...
    'ecc_corrected', 9; ...
    'snapshot_ecc_words', 10};
for output_index = 1:size(ecc_outputs, 1)
    output_name = ecc_outputs{output_index, 1};
    output_port = ecc_outputs{output_index, 2};
    position = [1000 360 + (output_index - 1) * 42 1030 380 + (output_index - 1) * 42];
    add_model_output(model_name, 'ECC_Memory', output_port, output_name, position);
end

add_line(model_name, 'snapshot_trigger/1', 'ECC_Memory/1', 'autorouting', 'on');
add_line(model_name, 'sample_value/1', 'ECC_Memory/2', 'autorouting', 'on');
add_line(model_name, 'reference_level/1', 'ECC_Memory/3', 'autorouting', 'on');
add_line(model_name, 'payload_crc_in/1', 'ECC_Memory/4', 'autorouting', 'on');
add_line(model_name, 'error_mode/1', 'ECC_Memory/5', 'autorouting', 'on');

add_block('simulink/Signal Routing/Bus Selector', [model_name '/CRC_Status_Selector'], ...
    'OutputSignals', 'signal1,signal2', 'Position', [455 190 505 245]);
add_block('simulink/Sinks/Scope', [model_name '/Scope_CRC'], ...
    'NumInputPorts', '4', 'Position', [535 95 575 210]);
add_block('simulink/Sinks/Scope', [model_name '/Scope_ECC_Status'], ...
    'NumInputPorts', '4', 'Position', [850 300 895 400]);
add_block('simulink/Sinks/Scope', [model_name '/Scope_ECC_Data'], ...
    'NumInputPorts', '2', 'Position', [850 100 895 165]);

add_line(model_name, 'Main_CRC/1', 'Scope_CRC/1', 'autorouting', 'on');
add_line(model_name, 'Main_CRC/2', 'Scope_CRC/2', 'autorouting', 'on');
add_line(model_name, 'Main_CRC/3', 'CRC_Status_Selector/1', 'autorouting', 'on');
add_line(model_name, 'CRC_Status_Selector/1', 'Scope_CRC/3', 'autorouting', 'on');
add_line(model_name, 'CRC_Status_Selector/2', 'Scope_CRC/4', 'autorouting', 'on');
add_line(model_name, 'ECC_Memory/1', 'Scope_ECC_Data/1', 'autorouting', 'on');
add_line(model_name, 'ECC_Memory/3', 'Scope_ECC_Data/2', 'autorouting', 'on');
add_line(model_name, 'ECC_Memory/2', 'Scope_ECC_Status/1', 'autorouting', 'on');
add_line(model_name, 'ECC_Memory/5', 'Scope_ECC_Status/2', 'autorouting', 'on');
add_line(model_name, 'ECC_Memory/8', 'Scope_ECC_Status/3', 'autorouting', 'on');
add_line(model_name, 'ECC_Memory/9', 'Scope_ECC_Status/4', 'autorouting', 'on');

set_param(model_name, ...
    'Solver', 'VariableStepAuto', ...
    'StopTime', '10', ...
    'SaveOutput', 'on', ...
    'OutputSaveName', 'yout', ...
    'SaveFormat', 'Dataset', ...
    'SaveTime', 'on', ...
    'SaveState', 'off', ...
    'SignalLogging', 'off', ...
    'ReturnWorkspaceOutputs', 'on');

set_param(model_name, 'SimulationCommand', 'update');
save_system(model_name, model_path);
close_system(model_name, 0);
end

function add_model_output(model_name, source_name, source_port, output_name, position)
output_path = [model_name '/' output_name];
add_block('simulink/Ports & Subsystems/Out1', output_path, 'Position', position);
add_line(model_name, [source_name '/' num2str(source_port)], ...
    [output_name '/1'], 'autorouting', 'on');
end