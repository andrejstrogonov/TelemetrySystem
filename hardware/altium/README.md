# Altium preparation package

This folder is the import-ready logical design package for the Rev A PCB. No Altium Designer native project or libraries are present in the repository, so this is not a fabricated `.SchDoc`/`.PcbDoc` and is not fabrication-ready.

## Files

- `BOM.csv`: selected baseline parts, package targets, and open procurement/footprint checks.
- `NETS.csv`: logical connectivity grouped by power, ADC, FPGA, MCU, programming, USB, and RS-485 nets.
- `POWER_TREE.md`: the electrical power architecture to implement in Altium. There is no Simulink power model; the tracked `model/power_supply_subsystem.slx` is deleted.
- `PLACEMENT.csv`: connector/component placement constraints for the 120 x 80 mm PCB and single-front-panel enclosure.

## Selected schematic architecture

1. J1 12 V DC enters through a fuse, reverse-polarity MOSFET, and TVS.
2. TPS54302 generates 5V5. Two TPS62160 bucks generate 1V2 and 3V3; the 3V3 regulator enable is sequenced from `PG_1V2`.
3. MCP3201 digitizes the fixed 0..3.3 V Owon input. FPGA1 performs acquisition/CRC; FPGA2 performs SEC-DED/ring/snapshot; STM32G0B1 handles gateway framing and RS-485.
4. J3 is half-duplex RS-485 to the host. J4 USB-C is service only. J5-J7 remain independent SWD/JTAG headers.

The numeric switcher feedback values are starting calculations from the selected regulator reference voltages, not released values. Before a PCB release, verify all MPNs/package pinouts against current manufacturer datasheets, run the regulator design tool for inductor/compensation/capacitors, assign Gowin QN88 and STM32 pins, and run electrical-rule/thermal checks. Do not fabricate from the logical CSV netlist alone.