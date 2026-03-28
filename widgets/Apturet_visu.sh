#!/data/data/com.termux/files/usr/bin/bash
# Widget: Stop all background garden processes

stopped=0

for name in darzs_log darzs_web darzs_foto; do
    PID_FILE="$HOME/.${name}.pid"
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            kill "$PID"
            ((stopped++))
        fi
        rm -f "$PID_FILE"
    fi
done

if [ $stopped -gt 0 ]; then
    termux-toast -s "⏹️ Apturēti $stopped process(i)"
else
    termux-toast -s "ℹ️ Nav aktīvu procesu"
fi
