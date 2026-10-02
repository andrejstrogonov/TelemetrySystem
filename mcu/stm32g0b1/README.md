# STM32G0B1 telemetry gateway

This directory contains the portable telemetry parser/JSON core and the STM32 HAL DMA entry point. The HAL adapter expects a CubeMX-generated STM32G0B1 project to provide `main.h`, `hspi1`, `huart2`, `MX_GPIO_Init`, `MX_DMA_Init`, `MX_SPI1_Init`, `MX_USART2_UART_Init`, and `SystemClock_Config`.

## FPGA2 SPI frame, version 1

SPI master: STM32, mode 0, 8-bit, MSB-first, active-low `FPGA2_CS`. Each poll clocks one 34-byte response. Multi-byte fields are little-endian.

| Offset | Size | Field |
|---:|---:|---|
| 0 | 2 | ASCII `TS` sync |
| 2 | 1 | version, `1` |
| 3 | 1 | frame length, `34` |
| 4 | 4 | sequence |
| 8 | 4 | timestamp in milliseconds |
| 12 | 2 | sample, signed Q1.15 |
| 14 | 2 | reference, signed Q1.15 |
| 16 | 4 | sample CRC-32/MPEG-2 |
| 20 | 1 | flags: CRC_OK, ECC_CORRECTED, ECC_UNCORRECTABLE, ANOMALY, SNAPSHOT_READY, BUFFER_FULL, POWER_FAULT in bits 0..6 |
| 21 | 1 | system state |
| 22 | 2 | FPGA1 temperature, centi-degrees C |
| 24 | 2 | FPGA2 temperature, centi-degrees C |
| 26 | 2 | MCU temperature, centi-degrees C |
| 28 | 2 | input voltage, millivolts |
| 30 | 2 | fan PWM, hundredths of a percent |
| 32 | 2 | CRC-16/CCITT-FALSE over bytes 0..31, little-endian |

`ecc-logging` currently implements ECC storage/status, not the SPI slave serializer. FPGA2 RTL must expose this frame before the MCU can run end-to-end. Keep the byte layout synchronized with `telemetry_protocol.c` and CI fixtures.

## CubeMX wiring

- SPI1 is master, mode 0, 8-bit, with DMA TX/RX. `FPGA2_CS` is a GPIO output.
- USART2 is the RS-485 UART, 115200 8N1. `RS485_DE` drives the transceiver DE and `/RE` together.
- Enable DMA and the SPI/UART completion/error callbacks used by `main.c`.
- Configure `FPGA2_CS_GPIO_Port`, `FPGA2_CS_Pin`, `RS485_DE_GPIO_Port`, and `RS485_DE_Pin` in `main.h`.
- The UART sends one UTF-8 JSON document followed by CR/LF per valid SPI frame. The host bridge can expose its latest line as `/status`.

The checked-in C core uses integer formatting and does not require newlib float `printf`. This repository does not include STM32CubeG0/HAL startup sources or a board `.ioc`, so `main.c` is an integration source, not a standalone firmware binary.