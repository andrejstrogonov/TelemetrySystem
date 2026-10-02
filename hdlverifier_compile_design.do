# Временно отключаем мгновенный выход при ошибке, чтобы увидеть её в консоли
onerror { echo "=== ОБНАРУЖЕНА ОШИБКА В СКРИПТЕ ===" }

# Очищаем старую библиотеку (если она заблокирована, ModelSim об этом скажет)
if [file exists work] {
    vdel -all
}
vlib work

# Создаем проект с нуля
project new . compile_project
project open compile_project.mpf

# Проверяем физическое наличие файлов на диске E перед добавлением
set SRC1 "E:/matlabVerilog"
foreach f {crc_verify.v gowin_crc32_detector.v hamming_sec_ded_decoder.v} {
    if {![file exists "$SRC1/$f"]} {
        echo "❌ КРИТИЧЕСКАЯ ОШИБКА: Файл $SRC1/$f НЕ НАЙДЕН!"
    } else {
        project addfile "$SRC1/$f"
        echo "✅ Файл $f добавлен в проект"
    }
}

# Расчет порядка и компиляция
project calculateorder
set compcmd [project compileall -n]
project close

echo "=== Запуск компиляции файлов ==="
eval $compcmd
echo "=== Скрипт завершил работу ==="

