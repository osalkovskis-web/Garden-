#!/data/data/com.termux/files/usr/bin/bash
# Dependency check and auto-install for garden monitoring system

PASS="✅"
FAIL="❌"
WARN="⚠️"

echo ""
echo "🌱 Dārza sistēmas uzstādīšanas pārbaude"
echo "========================================"
echo ""

all_ok=true

check_pkg() {
    local name=$1
    if dpkg -s "$name" &>/dev/null; then
        echo "$PASS pkg: $name"
    else
        echo "$WARN pkg: $name — instalē..."
        if pkg install -y "$name" &>/dev/null; then
            echo "$PASS pkg: $name — instalēts"
        else
            echo "$FAIL pkg: $name — neizdevās instalēt"
            all_ok=false
        fi
    fi
}

check_py_pkg() {
    local name=$1
    if python -c "import $name" &>/dev/null; then
        echo "$PASS python: $name"
    else
        echo "$WARN python: $name — instalē..."
        if pip install "$name" -q; then
            echo "$PASS python: $name — instalēts"
        else
            echo "$FAIL python: $name — neizdevās instalēt"
            all_ok=false
        fi
    fi
}

check_cmd() {
    local cmd=$1
    local test_cmd=$2
    if eval "$test_cmd" &>/dev/null; then
        echo "$PASS cmd: $cmd"
    else
        echo "$FAIL cmd: $cmd — nestrādā"
        all_ok=false
    fi
}

echo "--- Pakotnes ---"
check_pkg termux-api
check_pkg python
check_pkg git
check_pkg curl
check_pkg jq

echo ""
echo "--- Python bibliotēkas ---"
check_py_pkg pandas
check_py_pkg matplotlib

echo ""
echo "--- Termux sensori ---"
# Test termux-location (just check binary exists)
if command -v termux-location &>/dev/null; then
    echo "$PASS cmd: termux-location"
else
    echo "$FAIL cmd: termux-location — pārbaudi vai Termux:API ir instalēts"
    all_ok=false
fi

# Test termux-sensor
if command -v termux-sensor &>/dev/null; then
    echo "$PASS cmd: termux-sensor"
else
    echo "$FAIL cmd: termux-sensor — pārbaudi vai Termux:API ir instalēts"
    all_ok=false
fi

# Test termux-battery-status
if command -v termux-battery-status &>/dev/null; then
    echo "$PASS cmd: termux-battery-status"
else
    echo "$FAIL cmd: termux-battery-status"
    all_ok=false
fi

echo ""
echo "--- Krātuve ---"
if [ -d "$HOME/storage/downloads" ]; then
    echo "$PASS storage/downloads pieejama"
else
    echo "$WARN storage nav uzstādīta — palaiž termux-setup-storage..."
    termux-setup-storage
fi

echo ""
echo "========================================"
if $all_ok; then
    echo "$PASS Viss kārtībā! Vari sākt ar: bash start.sh"
else
    echo "$WARN Dažas pārbaudes neizdevās. Lasi ziņojumus augstāk."
fi
echo ""
