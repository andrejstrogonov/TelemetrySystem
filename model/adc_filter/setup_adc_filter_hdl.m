%% Simulink Model Generation & Verilog/HDL Coder Configuration Script
% Target: Subsystem "ADC_Filter" (First FPGA)
% Goal: Safe fixed-point filtering, deterministic group delay, and clean Verilog extraction.

clear; clk = 1;

%% 1. Define Filter & System Parameters
Fs = 100e6;           % ADC Sampling Frequency: 100 MHz
Fpass = 10e6;         % Passband: 10 MHz
Fstop = 15e6;         % Stopband: 15 MHz
Apass = 0.1;          % Passband Ripple (dB)
Astop = 60;           % Stopband Attenuation (dB)

% Calculate Equiripple FIR filter (compatible with HDL Coder)
lpFilter = designfilt('lowpassfir', ...
    'PassbandFrequency', Fpass, ...
    'StopbandFrequency', Fstop, ...
    'PassbandRipple', Apass, ...
    'StopbandAttenuation', Astop, ...
    'SampleRate', Fs);

b_coeff = lpFilter.Coefficients;
filter_order = length(b_coeff) - 1;
group_delay_ticks = filter_order / 2; % Deterministic latency for FIR

fprintf('Filter calculated. Order: %d, Latency: %d clock cycles.\n', filter_order, group_delay_ticks);

%% 2. Create and Configure Simulink Model
model_name = 'ADC_Filter_System';
if bdIsLoaded(model_name)
    close_system(model_name, 0);
end
new_system(model_name);
open_system(model_name);

% Set Solver Options essential for Fixed-Point and HDL Generation
set_param(model_name, 'SolverType', 'Fixed-step');
set_param(model_name, 'Solver', 'FixedStepDiscrete');
set_param(model_name, 'FixedStep', num2str(1/Fs));

%% 3. Create the Main Subsystem "ADC_Filter"
subsystem_path = [model_name '/ADC_Filter'];
add_block('built-in/Subsystem', subsystem_path);

% Inside Subsystem: Add Ports
add_block('built-in/Inport',  [subsystem_path '/In_Raw_Signal']);
add_block('built-in/Outport', [subsystem_path '/Out_Filtered_Signal']);

% Inside Subsystem: Add Quantizer (Simulated ADC via Data Type Conversion)
% Note: Using Data Type Conversion instead of standard Quantizer block is highly 
% recommended for native HDL code extraction to strictly enforce word lengths.
add_block('built-in/DataTypeConversion', [subsystem_path '/ADC_Quantizer']);
set_param([subsystem_path '/ADC_Quantizer'], 'OutDataTypeStr', 'fixdt(1,16,15)'); % 16-bit signed, 15-bit fraction
set_param([subsystem_path '/ADC_Quantizer'], 'RndMeth', 'Nearest');
set_param([subsystem_path '/ADC_Quantizer'], 'SaturateOnIntegerOverflow', 'on');

% Inside Subsystem: Add Discrete FIR Filter
add_block('simulink/Discrete/Discrete FIR Filter', [subsystem_path '/FIR_Filter']);
set_param([subsystem_path '/FIR_Filter'], 'Coefficients', 'b_coeff');
set_param([subsystem_path '/FIR_Filter'], 'InputProcessing', 'Elements as channels (sample based)');
% Fixed-point attributes for HDL optimization
set_param([subsystem_path '/FIR_Filter'], 'CoefDataTypeStr', 'fixdt(1,16,15)');
set_param([subsystem_path '/FIR_Filter'], 'ProductDataTypeStr', 'fixdt(1,32,30)');
set_param([subsystem_path '/FIR_Filter'], 'AccumDataTypeStr', 'fixdt(1,34,30)');
set_param([subsystem_path '/FIR_Filter'], 'OutputDataTypeStr', 'fixdt(1,16,15)');

% Inside Subsystem: Add Unit Delay for Transport Latency Matching
add_block('built-in/UnitDelay', [subsystem_path '/Pipeline_Delay']);
set_param([subsystem_path '/Pipeline_Delay'], 'X0', '0');
set_param([subsystem_path '/Pipeline_Delay'], 'SampleTime', num2str(1/Fs));

%% 4. Wire Blocks Inside Subsystem
add_line(subsystem_path, 'In_Raw_Signal/1', 'ADC_Quantizer/1', 'autorouting', 'on');
add_line(subsystem_path, 'ADC_Quantizer/1', 'FIR_Filter/1', 'autorouting', 'on');
add_line(subsystem_path, 'FIR_Filter/1', 'Pipeline_Delay/1', 'autorouting', 'on');
add_line(subsystem_path, 'Pipeline_Delay/1', 'Out_Filtered_Signal/1', 'autorouting', 'on');

%% 5. Add External Stimulus for Verification
add_block('simulink/Sources/Sine Wave', [model_name '/Noise_Signal']);
set_param([model_name '/Noise_Signal'], 'Frequency', '2*pi*35e6', 'SampleTime', num2str(1/Fs)); % 35 MHz High-frequency noise

add_block('simulink/Sources/Sine Wave', [model_name '/Pure_Signal']);
set_param([model_name '/Pure_Signal'], 'Frequency', '2*pi*2e6', 'SampleTime', num2str(1/Fs));   % 2 MHz Useful signal

add_block('simulink/Math Operations/Sum', [model_name '/Sum_ADC_Input']);
add_block('simulink/Sinks/Terminator', [model_name '/Terminator']);

% Wire Outer Testbench
add_line(model_name, 'Pure_Signal/1', 'Sum_ADC_Input/1', 'autorouting', 'on');
add_line(model_name, 'Noise_Signal/1', 'Sum_ADC_Input/2', 'autorouting', 'on');
add_line(model_name, 'Sum_ADC_Input/1', 'ADC_Filter/1', 'autorouting', 'on');
add_line(model_name, 'ADC_Filter/1', 'Terminator/1', 'autorouting', 'on');

%% 6. Configure Model for Direct Verilog Extraction (HDL Coder Setup)
% This configures the target language, clock signals, and resets to generate clean, readable Verilog.
hdl_cfg = hdlcoder.config;
set_param(model_name, 'HDLSubsystem', subsystem_path);
set_param(model_name, 'TargetLanguage', 'Verilog');
set_param(model_name, 'ResetType', 'Synchronous');
set_param(model_name, 'ResetAssertedLevel', 'Active-high');
set_param(model_name, 'ClockInputs', 'Single');
set_param(model_name, 'ClockEnableInputPort', 'clk_enable');
set_param(model_name, 'MinimizeClockEnables', 'on');
set_param(model_name, 'OptimizeForHDL', 'on');

% Save model setup
save_system(model_name);

disp('------------------------------------------------------------');
disp('Simulink architecture successfully generated and optimized!');
disp('To compile and extract Verilog, run command:');
disp(['>> makehdl(''', subsystem_path, ''')']);
disp('------------------------------------------------------------');
