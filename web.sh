#!/data/data/com.termux/files/usr/bin/bash
# Install Flask if needed and start the web dashboard

echo ""
echo "🌐 Dārza web monitors"
echo "====================="

# Install Flask if missing
if ! python3 -c "import flask" &>/dev/null; then
    echo "📦 Instalē Flask..."
    pip install flask -q
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$SCRIPT_DIR/web_server.py"
