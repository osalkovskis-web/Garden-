#!/data/data/com.termux/files/usr/bin/bash
# Widget: Start web dashboard and open browser

REPO="$HOME/Garden-"
PID_FILE="$HOME/.darzs_web.pid"

# Install Flask if missing (silent)
python3 -c "import flask" 2>/dev/null || pip install flask -q

# Check if server already running
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    termux-toast "🌐 Dashboard jau darbojas — atver pārlūku..."
    termux-open-url "http://localhost:8080"
    exit 0
fi

termux-toast "🌐 Startē web dashboard..."

nohup python3 "$REPO/web_server.py" \
    > "$HOME/.darzs_web.log" 2>&1 &

echo $! > "$PID_FILE"

# Wait for server to be ready (max 8s)
for i in 1 2 3 4 5 6 7 8; do
    sleep 1
    if curl -s http://localhost:8080 > /dev/null 2>&1; then
        termux-toast -s "✅ Dashboard gatavs!"
        termux-open-url "http://localhost:8080"
        exit 0
    fi
done

termux-toast -s "❌ Dashboard nestartēja. Pārbaudi: ~/.darzs_web.log"
