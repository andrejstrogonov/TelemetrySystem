Система телеметрии входящих пакетов с помощью CRC-32 на основе FPGA GoWin
С дополнительными функциями в виде Registered ECC (Hamming Window), Dual-Path Logging

Отдельный двухпортовый Ethernet-фильтр на Gowin FPGA находится в [ethernet-filter](ethernet-filter/README.md). Он сохраняет питание 12 В, проверяет Ethernet CRC и применяет синтезируемую целочисленную линейную регрессию к признакам заголовка.
