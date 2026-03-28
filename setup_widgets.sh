#!/data/data/com.termux/files/usr/bin/bash
# Creates Termux:Widget home screen shortcuts
# After running this, long-press home screen → Widgets → Termux:Widget

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHORTCUTS="$HOME/.shortcuts"

mkdir -p "$SHORTCUTS"

echo ""
echo "📱 Uzstāda sākumekrāna saīsnes..."
echo ""

# Copy each widget script
cp "$REPO_DIR/widgets/Sakt_logging.sh"      "$SHORTCUTS/Sakt_logging.sh"
cp "$REPO_DIR/widgets/Atvērt_dashboard.sh"  "$SHORTCUTS/Atvērt_dashboard.sh"
cp "$REPO_DIR/widgets/Foto_logging.sh"      "$SHORTCUTS/Foto_logging.sh"
cp "$REPO_DIR/widgets/Kopsavilkums.sh"      "$SHORTCUTS/Kopsavilkums.sh"
cp "$REPO_DIR/widgets/Apturet_visu.sh"      "$SHORTCUTS/Apturet_visu.sh"

chmod +x "$SHORTCUTS"/*.sh

echo "✅ Saīsnes izveidotas:"
ls "$SHORTCUTS"/*.sh | xargs -n1 basename
echo ""
echo "📋 Nākamie soļi:"
echo "   1) Turiet nospiestu tukšu vietu sākumekrānā"
echo "   2) Izvēlieties 'Logrīki' (Widgets)"
echo "   3) Atrodiet 'Termux:Widget'"
echo "   4) Velciet uz sākumekrānu"
echo "   5) Katrs poga ir atsevišķa saīsne"
echo ""
