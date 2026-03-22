#!/usr/bin/env bash
# ============================================================
#  cpu_monitor.sh  —  CPU yük dedektörü
#  Kullanım: bash cpu_monitor.sh [eşik%] [aralık_saniye]
#  Örnek:    bash cpu_monitor.sh 80 3
# ============================================================

THRESHOLD=${1:-80}      # %CPU eşiği (varsayılan: 80)
INTERVAL=${2:-3}        # örnekleme aralığı (saniye)
LOG="cpu_alert_$(date +%Y%m%d_%H%M%S).log"

RED='\033[1;31m'; YEL='\033[1;33m'; CYN='\033[1;36m'
GRN='\033[1;32m'; BLD='\033[1m'; RST='\033[0m'

divider() { printf '%0.s─' {1..72}; echo; }

header() {
    clear
    echo -e "${CYN}${BLD}"
    echo "  ██████╗██████╗ ██╗   ██╗    ███╗   ███╗ ██████╗ ███╗  ██╗"
    echo "  ██╔════╝██╔══██╗██║   ██║    ████╗ ████║██╔═══██╗████╗ ██║"
    echo "  ██║     ██████╔╝██║   ██║    ██╔████╔██║██║   ██║██╔██╗██║"
    echo "  ██║     ██╔═══╝ ██║   ██║    ██║╚██╔╝██║██║   ██║██║╚████║"
    echo "  ╚██████╗██║     ╚██████╔╝    ██║ ╚═╝ ██║╚██████╔╝██║ ╚███║"
    echo "   ╚═════╝╚═╝      ╚═════╝     ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚══╝"
    echo -e "${RST}"
    echo -e "  Eşik: ${YEL}%${THRESHOLD}${RST}  |  Aralık: ${YEL}${INTERVAL}s${RST}  |  Log: ${YEL}${LOG}${RST}"
    divider
}

# ── 1. SİSTEM ÖZETİ ─────────────────────────────────────────
system_summary() {
    echo -e "\n${BLD}[ SİSTEM BİLGİSİ ]${RST}"
    divider

    # lscpu — çekirdek ve frekans bilgisi
    echo -e "${CYN}▶ CPU modeli ve çekirdek sayısı (lscpu):${RST}"
    lscpu | grep -E \
        "^Model name|^CPU\(s\)|^Thread|^Core|^Socket|^CPU MHz|^CPU max MHz|^Virtualization|^Hypervisor" \
        | sed 's/^/  /'

    # Bellek
    echo -e "\n${CYN}▶ Bellek durumu (free -h):${RST}"
    free -h | grep -E "^Mem|^Swap|^total" | sed 's/^/  /'
}

# ── 2. ANLIK YÜKSEK CPU PROSESLERİ ──────────────────────────
top_processes() {
    echo -e "\n${BLD}[ EN YÜKSEK CPU KULLANAN PROSESLER ]${RST}"
    divider
    echo -e "${CYN}▶ ps aux --sort=-%cpu | head -11:${RST}"

    # Başlık satırı + ilk 10 proses
    ps aux --sort=-%cpu | head -11 | awk '
    NR==1 { printf "  \033[1m%-10s %-6s %-6s %-6s %s\033[0m\n", $1,$2,$3,$4,$11; next }
    {
        cpu=$3+0
        color="\033[0m"
        if (cpu >= 80) color="\033[1;31m"
        else if (cpu >= 40) color="\033[1;33m"
        printf "  %s%-10s %-6s %-6s %-6s %s\033[0m\n", color,$1,$2,$3,$4,$11
    }'
}

# ── 3. MPSTAT — ÇEKİRDEK BAŞINA YÜK ────────────────────────
per_core() {
    echo -e "\n${BLD}[ ÇEKİRDEK BAŞINA CPU KULLANIMI (mpstat) ]${RST}"
    divider

    if ! command -v mpstat &>/dev/null; then
        echo -e "  ${YEL}mpstat bulunamadı. Kur: sudo apt install sysstat${RST}"
        return
    fi

    echo -e "${CYN}▶ mpstat -P ALL 1 1:${RST}"
    mpstat -P ALL 1 1 | grep -E "^[0-9]|^Average|CPU" | awk '
    /CPU/ { printf "  \033[1m%-6s %-8s %-8s %-8s %-8s\033[0m\n",$2,$4,$6,$7,$13; next }
    {
        idle=$NF+0
        usr=$3+0
        color="\033[0m"
        if (idle < 20) color="\033[1;31m"
        else if (idle < 50) color="\033[1;33m"
        printf "  %s%-6s %-8s %-8s %-8s %-8s\033[0m\n",color,$2,$4,$6,$7,$NF
    }'
}

# ── 4. SICAKLIK SENSÖRLER ────────────────────────────────────
temperature() {
    echo -e "\n${BLD}[ SICAKLIK SENSÖRLERI (sensors) ]${RST}"
    divider

    if ! command -v sensors &>/dev/null; then
        echo -e "  ${YEL}sensors bulunamadı. Kur: sudo apt install lm-sensors && sudo sensors-detect${RST}"
        return
    fi

    echo -e "${CYN}▶ sensors (kritik değerler vurgulanır):${RST}"
    sensors | grep -E "°C|temp|Package|Core|Tdie|Tccd" | while IFS= read -r line; do
        # Sıcaklık değerini satırdan çek (+85.0°C gibi)
        temp=$(echo "$line" | grep -oP '\+\K[0-9]+(?=\.[0-9]+°C|°C)' | head -1)
        color=""
        reset="\033[0m"
        if [ -n "$temp" ]; then
            if   [ "$temp" -ge 90 ]; then color="\033[1;31m"
            elif [ "$temp" -ge 75 ]; then color="\033[1;33m"
            fi
        fi
        printf "  %b%s%b\n" "$color" "$line" "$reset"
    done
}

# ── 5. TOP ÖZETI ─────────────────────────────────────────────
top_summary() {
    echo -e "\n${BLD}[ TOP — ÖZET SATIRI ]${RST}"
    divider
    echo -e "${CYN}▶ top -bn1 (load average + CPU/bellek özeti):${RST}"
    top -bn1 | grep -E "^(%Cpu|MiB|load average|Tasks)" | sed 's/^/  /'
}

# ── 6. ŞÜPHELI PROSES TARAMASI ───────────────────────────────
suspicious_scan() {
    echo -e "\n${BLD}[ ŞÜPHELI PROSES TARAMASI ]${RST}"
    divider

    # Aynı komut adından birden fazla çalışan (fork/kopyalama belirtisi)
    echo -e "${CYN}▶ Aynı isimde çok sayıda proses (fork/spawn şüphesi):${RST}"
    ps aux | awk '{print $11}' | sort | uniq -c | sort -rn | head -10 | \
    awk '{
        color="\033[0m"
        if ($1 >= 10) color="\033[1;31m"
        else if ($1 >= 4) color="\033[1;33m"
        printf "  %s%4d × %s\033[0m\n", color, $1, $2
    }'

    # Eşiği aşan prosesler
    echo -e "\n${CYN}▶ CPU kullanımı >%${THRESHOLD} olan prosesler:${RST}"
    FOUND=0
    while IFS= read -r line; do
        CPU=$(echo "$line" | awk '{print $3}' | cut -d. -f1)
        if [ "$CPU" -ge "$THRESHOLD" ] 2>/dev/null; then
            echo -e "  ${RED}${line}${RST}"
            FOUND=1
        fi
    done < <(ps aux --sort=-%cpu | grep -v $$ | grep -v "ps aux" | head -11)

    [ "$FOUND" -eq 0 ] && echo -e "  ${GRN}Eşiği aşan proses yok (<%${THRESHOLD})${RST}"
}

# ── ANA DÖNGÜ ────────────────────────────────────────────────
main() {
    # Bağımlılık kontrolü
    for cmd in ps free lscpu; do
        command -v "$cmd" &>/dev/null || { echo "Eksik: $cmd"; exit 1; }
    done

    # İlk geçişte sistem özetini göster
    header
    system_summary
    echo -e "\n${GRN}Döngü başlıyor... Çıkmak için Ctrl+C${RST}\n"
    sleep 2

    PASS=0
    while true; do
        PASS=$((PASS+1))
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

        header
        echo -e "  ${BLD}Geçiş #${PASS}${RST}  |  ${TIMESTAMP}"

        top_summary
        per_core
        top_processes
        suspicious_scan
        temperature

        # ── UYARI: eşik aşıldıysa log'a yaz ──
        HIGH=$(ps aux --sort=-%cpu | grep -v $$ | grep -v "ps aux" | awk -v t="$THRESHOLD" \
    '$3+0 >= t {print}')
        if [ -n "$HIGH" ]; then
            {
                echo "=== UYARI: ${TIMESTAMP} ==="
                echo "$HIGH"
                echo ""
            } >> "$LOG"
            echo -e "\n  ${RED}⚠  UYARI log'a yazıldı → ${LOG}${RST}"
        fi

        echo -e "\n  ${YEL}Sonraki tarama ${INTERVAL} saniye sonra...${RST}"
        sleep "$INTERVAL"
    done
}

main
