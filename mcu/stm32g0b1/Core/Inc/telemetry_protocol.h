#ifndef TELEMETRY_PROTOCOL_H
#define TELEMETRY_PROTOCOL_H

#include <stddef.h>
#include <stdint.h>

#define TELEMETRY_FPGA_FRAME_SIZE 34u
#define TELEMETRY_JSON_CAPACITY 640u

#define TELEMETRY_FLAG_CRC_OK              (1u << 0)
#define TELEMETRY_FLAG_ECC_CORRECTED       (1u << 1)
#define TELEMETRY_FLAG_ECC_UNCORRECTABLE   (1u << 2)
#define TELEMETRY_FLAG_ANOMALY             (1u << 3)
#define TELEMETRY_FLAG_SNAPSHOT_READY      (1u << 4)
#define TELEMETRY_FLAG_BUFFER_FULL         (1u << 5)
#define TELEMETRY_FLAG_POWER_FAULT         (1u << 6)

typedef struct {
    uint32_t sequence;
    uint32_t timestamp_ms;
    int16_t sample_q15;
    int16_t reference_q15;
    uint32_t crc32;
    uint8_t flags;
    uint8_t system_state;
    int16_t fpga1_temperature_centi_c;
    int16_t fpga2_temperature_centi_c;
    int16_t mcu_temperature_centi_c;
    uint16_t input_voltage_mv;
    uint16_t fan_pwm_hundredths;
} telemetry_frame_t;

uint16_t telemetry_crc16_ccitt(const uint8_t *data, size_t length);
int telemetry_decode_fpga_frame(const uint8_t *buffer, size_t length, telemetry_frame_t *frame);
int telemetry_format_status_json(const telemetry_frame_t *frame, char *output, size_t capacity);

#endif