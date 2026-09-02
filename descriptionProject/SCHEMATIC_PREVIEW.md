## Принципиальная схема соединений (UML-подобная)
componentDiagram
    title UML Component Diagram: отказоустойчивая система сбора телеметрии (CRC32 + ECC)

    component "Power" as Power {
        port "Vin" as Power_Vin
        port "Vout_5.5V" as Power_Vout
        port "fault_flags" as Power_Fault
    }

    component "Plant (объект + возмущения)" as Plant {
        port "(in) input_signal" as Plant_In
        port "(out) output_signal / y[k]" as Plant_Out
        port "(out) w[k], v[k] (возмущения)" as Plant_Noise
    }

    component "ADC" as ADC {
        port "(in) signal_In" as ADC_In
        port "(out) signal_Out" as ADC_Out
    }

    component "ADC_Filter (DSP)" as Filter {
        port "(in) signal_In" as Filter_In
        port "(out) signal_out" as Filter_Out
    }

    component "CRC_Chain (CRC32)" as CRC {
        port "(in) dataIn" as CRC_In
        port "(in) startIn" as CRC_StartIn
        port "(out) dataOut" as CRC_Out
        port "(out) startOut" as CRC_StartOut
        port "(out) validEndOut" as CRC_Valid
        port "(out) errFlag" as CRC_Err
    }

    component "ChannelErr (инъекция ошибок канала)" as ChannelErr {
        port "(in) dataIn" as Channel_In
        port "(in) inject_err" as Channel_ErrIn
        port "(out) dataOut" as Channel_Out
    }

    component "ECC_Chain (Encoder)" as ECC_Enc {
        port "(in) data" as ECC_Enc_In
        port "(in) write_en" as ECC_Enc_Write
        port "(in) inject_bit_err" as ECC_Enc_ErrIn
        port "(out) encoded_data" as ECC_Enc_Out
    }

    component "RAM_Ring (кольцевой буфер)" as RAM {
        port "(in) data_in" as RAM_In
        port "(out) data_out" as RAM_Out
    }

    component "ECC_Chain (Decoder)" as ECC_Dec {
        port "(in) data" as ECC_Dec_In
        port "(in) read_addr" as ECC_Dec_Addr
        port "(out) data_out" as ECC_Dec_Out
        port "(out) ecc_corrected" as ECC_Dec_Corr
        port "(out) ecc_uncorrectable" as ECC_Dec_Uncorr
    }

    component "AnomalyDet (порог >30%)" as Anomaly {
        port "(in) filtered_signal" as Anom_InSig
        port "(in) ref_level" as Anom_Ref
        port "(in) delta_thresh" as Anom_Thresh
        port "(out) anomaly_flag" as Anom_Flag
        port "(out) delta_e" as Anom_Delta
    }

    component "Stateflow (автомат состояний)" as Stateflow {
        port "(in) anomaly_flag" as SF_Anom
        port "(in) ecc_flags" as SF_ECC
        port "(in) crc_err" as SF_CRC
        port "(in) snapshot_req" as SF_SnapReq
        port "(out) state_id" as SF_State
        port "(out) log_enable" as SF_LogEn
        port "(out) path_select" as SF_PathSel
        port "(out) retry_req" as SF_Retry
        port "(out) snapshot_ready" as SF_SnapReady
    }

    component "DualPath Log Storage" as DualPath {
        port "(in) ecc_data" as DP_Data
        port "(in) log_enable" as DP_LogEn
        port "(in) path_select" as DP_PathSel
        port "(in) timestamp" as DP_TS
        port "(out) pathA_out" as DP_A
        port "(out) pathB_out" as DP_B
        port "(out) snapshot_data" as DP_Snap
        port "(out) buffer_full" as DP_Full
    }

    component "Gateway_STM32" as STM {
        port "(in) crc_error" as STM_CRC
        port "(in) ecc_flags" as STM_ECC
        port "(in) anomaly" as STM_Anom
        port "(in) snapshot_trigger" as STM_SnapTrig
        port "(in) data" as STM_Data
        port "(in) state_id" as STM_State
        port "(out) output_bytes (JSON)" as STM_Out
    }

    component "Net (канал передачи)" as Net {
        port "(in) tx_data" as Net_In
        port "(out) telemetry" as Net_Out
    }

    component "InjectBitErr (тест ECC)" as InjectBit {
        port "(out) inject_bit_err" as Inject_Out
    }


    %% Соединения: выход → вход с размерностями/смыслом
    Power_Vout --> Plant_In : питание объекта
    Power_Fault --> STM_ECC : флаги ошибок питания → телеметрия

    Plant_Out --> ADC_In : y[k] → квантование
    Plant_Noise --> ChannelErr_ErrIn : w[k],v[k] → ошибки канала
    Plant_Noise --> Inject_Out : w[k],v[k] → тестовые битовые ошибки

    ADC_Out --> Filter_In : квантованный сигнал
    Filter_Out --> CRC_In : поток для CRC
    Filter_Out --> ECC_Enc_In : данные для ECC кодирования
    Filter_Out --> Anom_InSig : сигнал для детекции аномалий

    CRC_In --> CRCGen : данные на CRC
    CRC_StartIn --> const_start : старт пакета (константа/автомат)
    CRC_Out --> Channel_In : передача через канал с ошибками
    Channel_Out --> CRCDet : искажённые данные на детектор
    CRCDet --> STM_CRC : errFlag → телеметрия
    CRCDet --> SF_CRC : validEndOut → автомат состояний

    ECC_Enc_Out --> RAM_In : запись в буфер в кодовом виде
    RAM_Out --> ECC_Dec_In : чтение для декодирования
    ECC_Dec_Out --> DualPath_Data : восстановленные данные
    ECC_Dec_Corr --> STM_ECC : флаг коррекции → телеметрия
    ECC_Dec_Uncorr --> SF_ECC : неисправимая ошибка → автомат

    Anom_Flag --> SF_Anom : событие аномалии
    SF_LogEn --> DualPath_LogEn : разрешение записи
    SF_PathSel --> DualPath_PathSel : выбор пути A/B
    SF_SnapReady --> STM_SnapTrig : триггер снимка

    DualPath_Snap --> STM_Data : «снимок» аварии → телеметрия
    DualPath_A --> (scope/file) : поток A (опц.)
    DualPath_B --> (scope/file) : поток B (опц.)

    STM_Out --> Net_In : JSON‑телеметрия → сеть
    Net_Out --> Output : итоговые данные

    Inject_Out --> ECC_Enc_ErrIn : тестовые ошибки памяти


## 1. Распределение компонентов по чипам (Топология)

* **FPGA 1 (Gowin GW1N/GW2A): Тракт первичной обработки и контроля целостности**
  * `ADC_Filter (DSP)`
  * `CRC_Chain (CRC32)`
  * `ChannelErr`
  * `AnomalyDet`
* **FPGA 2 (Gowin GW1N/GW2A): Тракт помехоустойчивого кодирования и хранения**
  * `ECC_Chain (Encoder/Decoder)`
  * `RAM_Ring`
  * `DualPath Log Storage`
  * `InjectBitErr`
* **MCU (STM32F4/F7/H7): Координация, логика и интерфейсы**
  * `Stateflow (автомат состояний)`
  * `Gateway_STM32`

---

## 2. Схема шин питания (Power Distribution Network)

Для обеспечения отказоустойчивости и изоляции аналоговой/цифровой частей шина питания `Power` разделяется на следующие сегменты:

| Название шины | Номинал | Потребители | Назначение |
| :--- | :--- | :--- | :--- |
| **VCC_5V** | 5.0 В | ADC (Analog section), `Plant` (Датчики) | Первичное аналоговое питание |
| **VCC_3.3V** | 3.3 В | STM32 (V_DD), Gowin (V_CCIO), ADC (Digital) | Питание цифровых буферов ввода-вывода (I/O) |
| **VCC_1.2V** | 1.2 В | Gowin 1 & Gowin 2 (V_CC) | Питание ядер обеих ПЛИС (Core Power) |
| **VCC_1.8V** | 1.8 В | Gowin 1 & Gowin 2 (V_CCX) | Вспомогательное питание ПЛИС (Auxiliary) |
| **V_REF** | 2.5/3.0 В | ADC (V_REF) | Прецизионный источник опорного напряжения |

---

## 3. Спецификация информационных шин данных

Для связи между компонентами внутри кристаллов и между чипами формируются следующие унифицированные шины:

### 📊 Шина АЦП (Параллельная/SPI)
* **Соединение:** `ADC` -> `FPGA 1 (Filter_In)`
* **Состав:** `ADC_CLK` (такты), `ADC_DATA[11:0]` (12-битный параллельный код выборки), `ADC_DRDY` (готовность данных).

### 🎛️ Внутренняя шина ЦОС (Внутри FPGA 1)
* **Соединение:** `Filter_Out` -> `CRC_In` / `ECC_Enc_In` / `Anom_InSig`
* **Тип:** **AXI4-Stream (DSP profile)**
* **Состав:**
  * `tdata[15:0]`: Фильтрованный сигнал (16-бит со знаком).
  * `tvalid`: Флаг валидности отсчета.
  * `tlast`: Маркер конца кадра / пакета телеметрии.

### 🔀 Межплиточная шина данных (FPGA 1 -> FPGA 2)
* **Соединение:** Передача потока данных и контрольных сумм из `FPGA 1` в `FPGA 2`.
* **Тип:** **LVDS SPI / High-Speed Parallel**
* **Состав:** `FPGA_CLK`, `FPGA_DATA[7:0]`, `FPGA_FRAME` (кадрирование), `CRC_ERR_FLAG` (аварийный маркер прямого действия).

### 🧠 Локальная шина памяти и ECC (Внутри FPGA 2)
* **Соединение:** `ECC_Enc` -> `RAM_Ring` -> `ECC_Dec`
* **Тип:** **System Memory Bus**
* **Состав:**
  * `DATA_BUS[15:0]`: Информационные биты.
  * `ECC_BUS[5:0]`: Избыточные биты Хемминга (SEC-DED для 16-битного слова).
  * `WR_EN` / `RD_EN`: Сигналы записи и чтения кольцевого буфера.

### 🏛️ Системная шина управления и снимков (FPGA 2 <-> STM32)
* **Соединение:** Передача логов `DualPath` и флагов в `STM32`, возврат команд управления (`path_select`, `log_enable`).
* **Тип:** **FMC/FSMC (Flexible Static Memory Controller)** или высокоскоростной **SPI + DMA**
* **Состав:**
  * `STM_A[9:0]`: Шина адреса для чтения регистров аварийных снимков (Snapshot).
  * `STM_D[15:0]`: Шина данных (чтение восстановленных данных `DualPath_Snap`).
  * `CTRL_LINES`: `CS_N` (выбор чипа), `OE_N` (разрешение выхода), `WE_N` (разрешение записи).

### 🚨 Шина событий и прерываний (FPGA 1/2 -> STM32)
* **Соединение:** Аварийные флаги на GPIO‑входы STM32 с функцией EXTI (внешние прерывания) для `Stateflow`.
* **Состав линий (Discrete Lines):**
  * `IRQ_ANOMALY`: Флаг обнаружения аномалии (>30%).
  * `IRQ_ECC_UNCORR`: Сигнал критической (неисправимой) ошибки ОЗУ.
  * `IRQ_CRC_FAIL`: Сигнал искажения пакета в канале передачи.
  * `BUFF_FULL`: Сигнал заполнения лога `DualPath`.

### 🌐 Выходная шина телеметрии
* **Соединение:** `Gateway_STM32 (STM_Out)` -> `Net_In`
* **Тип:** **UART-to-Ethernet (или Wi-Fi/Can-Bus трансивер)**
* **Состав:** `TX`, `RX`, `RTS`, `CTS` (аппаратный контроль потока для исключения потери JSON-пакетов).

---

## 4. Аппаратная реализация узлов на схеме

1. **Инъекция ошибок (`ChannelErr` и `InjectBitErr`):** Реализуются внутри ПЛИС на базе XOR-маскирования шин данных. Триггером ошибки выступает генератор псевдослучайных чисел (LFSR), завязанный на шумовые отсчеты `w[k], v[k]`.
2. **Синхронизация:** Тактовые домены ПЛИС 1, ПЛИС 2 и STM32 синхронизируются внешним тактовым генератором (TCXO), подключенным к глобальным буферам тактирования (GCLK).

