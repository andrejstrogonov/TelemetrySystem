#include "main.h"
#include "telemetry_protocol.h"

#include <string.h>

extern SPI_HandleTypeDef hspi1;
extern UART_HandleTypeDef huart2;

static uint8_t spi_tx[TELEMETRY_FPGA_FRAME_SIZE];
static uint8_t spi_rx[TELEMETRY_FPGA_FRAME_SIZE];
static char json_line[TELEMETRY_JSON_CAPACITY];
static volatile uint8_t spi_busy;
static volatile uint8_t uart_busy;

static void begin_fpga_poll(void)
{
    memset(spi_tx, 0, sizeof(spi_tx));
    HAL_GPIO_WritePin(FPGA2_CS_GPIO_Port, FPGA2_CS_Pin, GPIO_PIN_RESET);
    spi_busy = 1u;
    if (HAL_SPI_TransmitReceive_DMA(&hspi1, spi_tx, spi_rx, TELEMETRY_FPGA_FRAME_SIZE) != HAL_OK) {
        spi_busy = 0u;
        HAL_GPIO_WritePin(FPGA2_CS_GPIO_Port, FPGA2_CS_Pin, GPIO_PIN_SET);
    }
}

int main(void)
{
    uint32_t last_poll_ms = 0u;

    HAL_Init();
    SystemClock_Config();
    MX_GPIO_Init();
    MX_DMA_Init();
    MX_SPI1_Init();
    MX_USART2_UART_Init();

    HAL_GPIO_WritePin(FPGA2_CS_GPIO_Port, FPGA2_CS_Pin, GPIO_PIN_SET);
    HAL_GPIO_WritePin(RS485_DE_GPIO_Port, RS485_DE_Pin, GPIO_PIN_RESET);

    while (1) {
        uint32_t now = HAL_GetTick();
        if (spi_busy == 0u && uart_busy == 0u && (uint32_t)(now - last_poll_ms) >= 100u) {
            last_poll_ms = now;
            begin_fpga_poll();
        }
    }
}

void HAL_SPI_TxRxCpltCallback(SPI_HandleTypeDef *spi)
{
    telemetry_frame_t frame;
    int json_length;

    if (spi != &hspi1) {
        return;
    }
    HAL_GPIO_WritePin(FPGA2_CS_GPIO_Port, FPGA2_CS_Pin, GPIO_PIN_SET);
    spi_busy = 0u;

    if (!telemetry_decode_fpga_frame(spi_rx, sizeof(spi_rx), &frame)) {
        return;
    }
    json_length = telemetry_format_status_json(&frame, json_line, sizeof(json_line));
    if (json_length <= 0) {
        return;
    }

    HAL_GPIO_WritePin(RS485_DE_GPIO_Port, RS485_DE_Pin, GPIO_PIN_SET);
    uart_busy = 1u;
    if (HAL_UART_Transmit_DMA(&huart2, (uint8_t *)json_line, (uint16_t)json_length) != HAL_OK) {
        uart_busy = 0u;
        HAL_GPIO_WritePin(RS485_DE_GPIO_Port, RS485_DE_Pin, GPIO_PIN_RESET);
    }
}

void HAL_UART_TxCpltCallback(UART_HandleTypeDef *uart)
{
    if (uart != &huart2) {
        return;
    }
    HAL_GPIO_WritePin(RS485_DE_GPIO_Port, RS485_DE_Pin, GPIO_PIN_RESET);
    uart_busy = 0u;
}

void HAL_SPI_ErrorCallback(SPI_HandleTypeDef *spi)
{
    if (spi == &hspi1) {
        HAL_GPIO_WritePin(FPGA2_CS_GPIO_Port, FPGA2_CS_Pin, GPIO_PIN_SET);
        spi_busy = 0u;
    }
}

void HAL_UART_ErrorCallback(UART_HandleTypeDef *uart)
{
    if (uart == &huart2) {
        HAL_GPIO_WritePin(RS485_DE_GPIO_Port, RS485_DE_Pin, GPIO_PIN_RESET);
        uart_busy = 0u;
    }
}