# TelemetrySystem CI

Run the complete deterministic verification from the repository root:

```matlab
addpath('ci');
run_ci
```

Requirements: MATLAB with Simulink, Stateflow, and Communications Toolbox; Node.js; Questa `vlog`/`vsim` for RTL tests. If Questa is not on PATH, set `QUESTA_VLOG` to the full path of `vlog.exe` before starting MATLAB. The CI runner locates the matching `vsim` and `vlib` beside it.

The run rebuilds `ecc_memory_subsystem.slx` and `sim_new_telemetry_system.slx`, verifies all 55 single-bit ECC positions and a double-bit error, runs the integrated main+ECC model, checks the 256+256 snapshot timing and 512x55 codewords, validates `status.json` with the Electron schema checker, runs Questa benches, and validates Altium CSV structure.

Generated outputs are written to `artifacts/ci/` and are ignored by Git:

- `integrated_signals.mat`
- `snapshot_signals.mat`
- `signals.png`
- `status.json`

This pipeline does not run Gowin synthesis/place-and-route, create an Altium native project, or build the STM32 HAL firmware. Those require the Gowin toolchain, Altium Designer, and STM32CubeG0/CubeMX sources respectively.