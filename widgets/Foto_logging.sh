#!/data/data/com.termux/files/usr/bin/bash
# Widget: Start photo watcher in background

REPO="$HOME/Garden-"
PID_FILE="$HOME/.darzs_foto.pid"

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    termux-toast -s "📸 Foto logging jau darbojas (PID $(cat $PID_FILE))"
    exit 0
fi

termux-toast "📸 Sāk foto uzraudzību..."

nohup bash "$REPO/foto_log.sh" \
    > "$HOME/.darzs_foto.log" 2>&1 &

echo $! > "$PID_FILE"
sleep 1

if kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    termux-toast -s "✅ Foto logging sākts! Uzņem bildes ar kameru."
else
    termux-toast -s "❌ Neizdevās sākt foto logging."
fi
