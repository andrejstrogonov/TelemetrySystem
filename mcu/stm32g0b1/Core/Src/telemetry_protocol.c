#include "telemetry_protocol.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static uint16_t read_u16_le(const uint8_t *data)
{
    return (uint16_t)data[0] | (uint16_t)((uint16_t)data[1] << 8);
}

static uint32_t read_u32_le(const uint8_t *data)
{
    return (uint32_t)data[0] |
           ((uint32_t)data[1] << 8) |
           ((uint32_t)data[2] << 16) |
           ((uint32_t)data[3] << 24);
}

uint16_t telemetry_crc16_ccitt(const uint8_t *data, size_t length)
{
    uint16_t crc = 0xFFFFu;
    size_t index;
    unsigned bit_index;

    for (index = 0; index < length; ++index) {
        crc ^= (uint16_t)data[index] << 8;
        for (bit_index = 0; bit_index < 8u; ++bit_index) {
            crc = (crc & 0x8000u) != 0u
                ? (uint16_t)((crc << 1) ^ 0x1021u)
                : (uint16_t)(crc << 1);
        }
    }
    return crc;
}

int telemetry_decode_fpga_frame(const uint8_t *buffer, size_t length, telemetry_frame_t *frame)
{
    uint16_t expected_crc;
    uint16_t actual_crc;

    if (buffer == NULL || frame == NULL || length != TELEMETRY_FPGA_FRAME_SIZE) {
        return 0;
    }
    if (buffer[0] != 'T' || buffer[1] != 'S' || buffer[2] != 1u || buffer[3] != TELEMETRY_FPGA_FRAME_SIZE) {
        return 0;
    }

    expected_crc = read_u16_le(&buffer[32]);
    actual_crc = telemetry_crc16_ccitt(buffer, 32u);
    if (expected_crc != actual_crc) {
        return 0;
    }

    frame->sequence = read_u32_le(&buffer[4]);
    frame->timestamp_ms = read_u32_le(&buffer[8]);
    frame->sample_q15 = (int16_t)read_u16_le(&buffer[12]);
    frame->reference_q15 = (int16_t)read_u16_le(&buffer[14]);
    frame->crc32 = read_u32_le(&buffer[16]);
    frame->flags = buffer[20];
    frame->system_state = buffer[21];
    frame->fpga1_temperature_centi_c = (int16_t)read_u16_le(&buffer[22]);
    frame->fpga2_temperature_centi_c = (int16_t)read_u16_le(&buffer[24]);
    frame->mcu_temperature_centi_c = (int16_t)read_u16_le(&buffer[26]);
    frame->input_voltage_mv = read_u16_le(&buffer[28]);
    frame->fan_pwm_hundredths = read_u16_le(&buffer[30]);
    return 1;
}

static int append_json(char *output, size_t capacity, size_t *used, const char *format, ...)
{
    int count;
    va_list arguments;

    if (*used >= capacity) {
        return 0;
    }
    va_start(arguments, format);
    count = vsnprintf(&output[*used], capacity - *used, format, arguments);
    va_end(arguments);
    if (count < 0 || (size_t)count >= capacity - *used) {
        return 0;
    }
    *used += (size_t)count;
    return 1;
}

static void format_fixed(char *output, size_t capacity, int32_t value, uint32_t scale, unsigned digits)
{
    uint32_t magnitude = (value < 0) ? (uint32_t)(-(int64_t)value) : (uint32_t)value;
    (void)snprintf(output, capacity, "%s%lu.%0*lu", value < 0 ? "-" : "",
        (unsigned long)(magnitude / scale), (int)digits, (unsigned long)(magnitude % scale));
}

static uint16_t deviation_percent(const telemetry_frame_t *frame)
{
    int32_t sample = frame->sample_q15;
    int32_t reference = frame->reference_q15;
    uint32_t difference = (sample >= reference)
        ? (uint32_t)(sample - reference)
        : (uint32_t)(reference - sample);
    uint32_t magnitude = (reference < 0) ? (uint32_t)(-reference) : (uint32_t)reference;

    if (magnitude == 0u) {
        return difference == 0u ? 0u : 100u;
    }
    return (uint16_t)((difference * 100u) / magnitude);
}

int telemetry_format_status_json(const telemetry_frame_t *frame, char *output, size_t capacity)
{
    char fpga1_temperature[20];
    char fpga2_temperature[20];
    char mcu_temperature[20];
    char input_voltage[20];
    char sample_voltage[20];
    uint16_t deviation;
    uint16_t fan_percent;
    uint8_t alarm;
    size_t used = 0u;
    int has_event;

    if (frame == NULL || output == NULL || capacity == 0u) {
        return 0;
    }

    format_fixed(fpga1_temperature, sizeof(fpga1_temperature), frame->fpga1_temperature_centi_c, 100u, 2u);
    format_fixed(fpga2_temperature, sizeof(fpga2_temperature), frame->fpga2_temperature_centi_c, 100u, 2u);
    format_fixed(mcu_temperature, sizeof(mcu_temperature), frame->mcu_temperature_centi_c, 100u, 2u);
    format_fixed(input_voltage, sizeof(input_voltage), frame->input_voltage_mv, 1000u, 3u);
    format_fixed(sample_voltage, sizeof(sample_voltage), ((int32_t)frame->sample_q15 * 3300) / 32768, 1000u, 3u);
    deviation = deviation_percent(frame);
    fan_percent = (uint16_t)(frame->fan_pwm_hundredths / 100u);
    alarm = (uint8_t)((frame->flags & (TELEMETRY_FLAG_ANOMALY | TELEMETRY_FLAG_ECC_UNCORRECTABLE | TELEMETRY_FLAG_POWER_FAULT)) != 0u);
    has_event = (frame->flags & (TELEMETRY_FLAG_ANOMALY | TELEMETRY_FLAG_ECC_UNCORRECTABLE)) != 0u;

    if (!append_json(output, capacity, &used,
        "{\"timestamp_ms\":%lu,\"temperatures_c\":{\"stm32\":%s,\"fpga_1\":%s,\"fpga_2\":%s,\"hotspot\":%s},",
        (unsigned long)frame->timestamp_ms, mcu_temperature, fpga1_temperature, fpga2_temperature,
        frame->fpga1_temperature_centi_c > frame->fpga2_temperature_centi_c ? fpga1_temperature : fpga2_temperature)) {
        return 0;
    }
    if (!append_json(output, capacity, &used,
        "\"power\":{\"voltage_v\":%s,\"status\":\"%s\"},",
        input_voltage, (frame->flags & TELEMETRY_FLAG_POWER_FAULT) ? "fault" : "ok")) {
        return 0;
    }
    if (!append_json(output, capacity, &used,
        "\"fan\":{\"pwm_percent\":%u,\"pin_fan_pwm\":\"PA0\",\"pin_exp\":\"PA1\",\"exp_flag\":%s},",
        (unsigned)fan_percent, alarm ? "true" : "false")) {
        return 0;
    }
    if (!append_json(output, capacity, &used,
        "\"crc\":{\"last_block_crc32\":\"0x%08lX\",\"ok\":%s},",
        (unsigned long)frame->crc32, (frame->flags & TELEMETRY_FLAG_CRC_OK) ? "true" : "false")) {
        return 0;
    }
    if (!append_json(output, capacity, &used,
        "\"ecc\":{\"corrected\":%s,\"uncorrectable\":%s,\"snapshot_ready\":%s,\"buffer_full\":%s},\"events\":[",
        (frame->flags & TELEMETRY_FLAG_ECC_CORRECTED) ? "true" : "false",
        (frame->flags & TELEMETRY_FLAG_ECC_UNCORRECTABLE) ? "true" : "false",
        (frame->flags & TELEMETRY_FLAG_SNAPSHOT_READY) ? "true" : "false",
        (frame->flags & TELEMETRY_FLAG_BUFFER_FULL) ? "true" : "false")) {
        return 0;
    }
    if (has_event) {
        if (!append_json(output, capacity, &used,
            "{\"type\":\"%s\",\"timestamp_ms\":%lu,\"value\":%s,\"deviation_percent\":%u}",
            (frame->flags & TELEMETRY_FLAG_ANOMALY) ? "anomaly_high_deviation" : "ecc_uncorrectable",
            (unsigned long)frame->timestamp_ms, sample_voltage, (unsigned)deviation)) {
            return 0;
        }
    }
    if (!append_json(output, capacity, &used,
        "],\"thresholds_c\":{\"target\":70.0,\"max_safe\":85.0},\"system\":{\"mode\":\"%s\",\"uptime_s\":%lu,\"sequence\":%lu,\"state_id\":%u}}\r\n",
        alarm ? "alarm" : "normal", (unsigned long)(frame->timestamp_ms / 1000u),
        (unsigned long)frame->sequence, (unsigned)frame->system_state)) {
        return 0;
    }

    return (int)used;
}