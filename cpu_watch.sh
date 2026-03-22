#!/usr/bin/env bash
# cpu_watch.sh — sade CPU izleyici
# Kullanım: bash cpu_watch.sh [eşik%] [aralık_saniye]

THRESHOLD=${1:-80}
INTERVAL=${2:-3}
LOG="cpu_alert_$(date +%Y%m%d_%H%M%S).log"

R='\033[1;31m' Y='\033[1;33m' G='\033[1;32m' B='\033[1;36m' Z='\033[0m'

while true; do
    clear
    echo -e "${B}$(date '+%H:%M:%S')${Z}  eşik:${Y}%${THRESHOLD}${Z}  log:${Y}${LOG}${Z}"
    echo "────────────────────────────────────────────────────"

    # Load average + CPU özeti
    top -bn1 | grep -E "^(%Cpu|load avg)" | sed 's/^/  /'

    # Çekirdek başına (mpstat varsa)
    if command -v mpstat &>/dev/null; then
        echo "  ---"
        mpstat -P ALL 1 1 2>/dev/null \
            | awk '/^[0-9]/ && $3!="CPU" {
                idle=$NF+0
                c=(idle<20)?"\033[1;31m":(idle<50)?"\033[1;33m":"\033[0m"
                printf "  %sCPU%-2s  usr:%-5s sys:%-5s idle:%-5s\033[0m\n",c,$3,$4,$6,$NF
            }'
    fi

    # Top 5 proses
    echo "  ---"
    ps aux --sort=-%cpu | grep -v $$ | grep -v "ps aux" | awk '
        NR==1 { next }
        NR>6  { exit }
        {
            c=($3+0>=80)?"\033[1;31m":($3+0>=40)?"\033[1;33m":"\033[0m"
            printf "  %s%-6s %-5s %s\033[0m\n",c,$3,$2,$11
        }'

    # Fork şüphesi (aynı isimde 5+ proses)
    SUSPICIOUS=$(ps aux | awk '{print $11}' | sort | uniq -c | awk '$1>=5 {print $1"×"$2}')
    [ -n "$SUSPICIOUS" ] && echo -e "  ${R}⚠ fork?${Z} $SUSPICIOUS"

    # Sıcaklık (sensors varsa)
    if command -v sensors &>/dev/null; then
        echo "  ---"
        sensors | grep -E "°C|Package|Core|Tdie" | while IFS= read -r line; do
            temp=$(echo "$line" | grep -oP '\+\K[0-9]+(?=[\.,][0-9]+°C|°C)' | head -1)
            c=""
            [ -n "$temp" ] && [ "$temp" -ge 90 ] && c="$R"
            [ -n "$temp" ] && [ "$temp" -ge 75 ] && [ "$temp" -lt 90 ] && c="$Y"
            printf "  %b%s\033[0m\n" "$c" "$line"
        done
    fi

    # Bellek (tek satır)
    echo "  ---"
    free -h | awk '/^Mem/ {printf "  mem: kullanılan:%-6s boş:%-6s toplam:%s\n",$3,$4,$2}'

    # Eşik aşıldıysa logla
    HIGH=$(ps aux --sort=-%cpu | grep -v $$ | grep -v "ps aux" | awk -v t="$THRESHOLD" '$3+0>=t')
    if [ -n "$HIGH" ]; then
        echo -e "\n  ${R}⚠  eşik aşıldı → ${LOG}${Z}"
        printf "=== %s ===\n%s\n\n" "$(date)" "$HIGH" >> "$LOG"
    fi

    sleep "$INTERVAL"
done
