#!/data/data/com.termux/files/usr/bin/bash
# Widget: Start continuous sensor logging in background

REPO="$HOME/Garden-"
PID_FILE="$HOME/.darzs_log.pid"

# Check if already running
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    termux-toast -s "📡 Logging jau darbojas (PID $(cat $PID_FILE))"
    exit 0
fi

termux-toast "📡 Sāk datu reģistrēšanu..."

nohup bash "$REPO/darzs_log.sh" \
    > "$HOME/storage/downloads/darzs_log_output.txt" 2>&1 &

echo $! > "$PID_FILE"
sleep 1

if kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    termux-toast -s "✅ Logging sākts! PID: $(cat $PID_FILE)"
else
    termux-toast -s "❌ Neizdevās sākt logging. Pārbaudi: darzs_log_output.txt"
fi
