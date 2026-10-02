# Rev A power tree for Altium

Input is the external Mean Well NGE12E12-P1J, 12 V DC / 1 A SELV adapter. Mains voltage stays outside the enclosure. This power tree replaces `power_supply_subsystem.slx`; rail behavior is an electrical Altium design concern, not a Simulink plant.

```text
J1 12V -> F1 1A -> Q1 reverse protection -> D1 TVS -> VIN_PROTECTED
VIN_PROTECTED -> U1 TPS54302 -> 5V5
5V5 -> U2 TPS62160 -> 1V2_CORE (FPGA1 + FPGA2)
5V5 -> U3 TPS62160 -> 3V3_IO (MCU, ADC, QSPI, RS-485, FPGA I/O)
PG_1V2 -> enable U3 -> PG_3V3
PG_5V5 & PG_1V2 & PG_3V3 -> POWER_GOOD indicator + MCU fault input
USB_VBUS -> service-only current-limited path; no connection to VIN/5V5
```

Preliminary feedback network calculations use a 0.596 V reference for U1 (`Rtop=82.5 kOhm`, `Rbottom=10.0 kOhm`, approximately 5.51 V) and 0.8 V for U2/U3 (`Rbottom=100 kOhm`; 316 kOhm for 3V3 and 49.9 kOhm for 1V2). Confirm against the exact regulator revision and chosen feedback-current limits before layout.

Design gates before release:

- Confirm U1/U2/U3 availability, exact pinout, and data-sheet reference voltage.
- Recalculate inductors, input/output capacitance, ripple, loop stability, startup, and load transients using the vendor design tool.
- Validate the 1V2-before-3V3 sequencing, PG thresholds, 1 A adapter budget, USB current limit, and reverse-current behavior.
- Keep 5V5 away from all digital I/O. All MCU/FPGA/ADC/RS-485 logic interfaces are 3V3.
- Add local decoupling at each FPGA power pin group and separate the ADC reference/analog return according to layout rules.