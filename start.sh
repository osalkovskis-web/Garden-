#!/data/data/com.termux/files/usr/bin/bash
# Master launcher with Latvian menu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

trap 'echo ""; echo "👋 Uz redzēšanos!"; exit 0' INT TERM

show_menu() {
    clear
    echo ""
    echo "🌱 ╔══════════════════════════════════╗"
    echo "   ║   DĀRZA MONITORINGA SISTĒMA     ║"
    echo "   ║   Kazas sēklis, Lucavsala       ║"
    echo "   ╚══════════════════════════════════╝"
    echo ""
    echo "   1) 📡 Sākt logging (ik 30s)"
    echo "   2) 🗺️  Augstuma uzmērīšana"
    echo "   3) 📸 Foto logging"
    echo "   4) 📊 Dienas kopsavilkums"
    echo "   5) 🔧 Pārbaudīt uzstādījumus"
    echo "   6) ❓ Palīdzība"
    echo "   0) 🚪 Iziet"
    echo ""
    echo -n "   Izvēlies (0-6): "
}

show_help() {
    clear
    echo ""
    echo "❓ PALĪDZĪBA"
    echo "============"
    echo ""
    echo "1) LOGGING — Automātiski pieraksta GPS, spiedienu,"
    echo "   gaismu un citus sensorus ik 30 sekundes."
    echo "   Dati tiek saglabāti Downloads mapē."
    echo ""
    echo "2) AUGSTUMA UZMĒRĪŠANA — Interaktīvs režīms."
    echo "   Dodies uz katru punktu dārzā un nospied ENTER."
    echo "   Sistēma veic 10 GPS nolasījumus un aprēķina"
    echo "   vidējo augstumu."
    echo ""
    echo "3) FOTO LOGGING — Uzrauga kameras mapi."
    echo "   Katram jaunam foto automātiski pieraksta"
    echo "   laiku, GPS koordinātes un augstumu."
    echo ""
    echo "4) KOPSAVILKUMS — Parāda šodienas statistiku:"
    echo "   spiedienu, augstumu, plūdu risku."
    echo ""
    echo "5) UZSTĀDĪJUMI — Pārbauda vai visi rīki ir"
    echo "   instalēti un darbojas pareizi."
    echo ""
    echo "📁 Visi dati tiek saglabāti:"
    echo "   ~/storage/downloads/"
    echo ""
    echo "⚠️  PLŪDU BRĪDINĀJUMI:"
    echo "   Spiediens krīt > 5 hPa = vētra"
    echo "   Augstums < 60cm = paaugstināts risks"
    echo "   Augstums < 30cm = augsts risks"
    echo ""
    read -rp "Nospied ENTER lai turpinātu..."
}

while true; do
    show_menu
    read -r choice

    case "$choice" in
        1)
            echo ""
            echo "🚀 Palaiž logging..."
            sleep 1
            bash "$SCRIPT_DIR/darzs_log.sh"
            ;;
        2)
            echo ""
            echo "🚀 Palaiž augstuma uzmērīšanu..."
            sleep 1
            bash "$SCRIPT_DIR/augstuma_karte.sh"
            read -rp "Nospied ENTER lai turpinātu..."
            ;;
        3)
            echo ""
            echo "🚀 Palaiž foto logging..."
            sleep 1
            bash "$SCRIPT_DIR/foto_log.sh"
            ;;
        4)
            echo ""
            bash "$SCRIPT_DIR/kopsavilkums.sh"
            read -rp "Nospied ENTER lai turpinātu..."
            ;;
        5)
            echo ""
            bash "$SCRIPT_DIR/check_setup.sh"
            read -rp "Nospied ENTER lai turpinātu..."
            ;;
        6)
            show_help
            ;;
        0)
            echo ""
            echo "👋 Uz redzēšanos!"
            exit 0
            ;;
        *)
            echo "   ❌ Nepareiza izvēle. Mēģini vēlreiz."
            sleep 1
            ;;
    esac
done
