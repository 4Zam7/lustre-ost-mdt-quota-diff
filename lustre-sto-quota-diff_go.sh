#!/bin/bash
# compare_quota.sh — compatible macOS (bash 3+, grep BSD, awk)
# Affichage en Go — colonnes: Filesystem | Go utilisé | limit avant | limit après | Δ limit
# Usage: ./compare_quota.sh <before_file> <after_file>

BEFORE="${1:-output-af3d60fn.txt}"
AFTER="${2:-output-af3d60fn_after_force_reint.txt}"

if [[ ! -f "$BEFORE" || ! -f "$AFTER" ]]; then
    echo "Usage: $0 <before_file> <after_file>"
    echo "  before_file : quota avant force_reint"
    echo "  after_file  : quota après force_reint"
    exit 1
fi

awk -v before="$BEFORE" -v after="$AFTER" '
function kb2gb(kb) {
    return sprintf("%.2f", kb / 1048576)
}

BEGIN {
    RED    = "\033[0;31m"
    GREEN  = "\033[0;32m"
    YELLOW = "\033[1;33m"
    BOLD   = "\033[1m"
    NC     = "\033[0m"

    # --- Parse BEFORE ---
    cur = ""
    while ((getline line < before) > 0) {
        if (line ~ /^[[:space:]]*(fscronos-[A-Za-z0-9_]+)/) {
            match(line, /fscronos-[A-Za-z0-9_]+/)
            cur = substr(line, RSTART, RLENGTH)
        } else if (cur != "" && line ~ /^[[:space:]]+[0-9]/) {
            n = split(line, f)
            gsub(/\*/, "", f[1])
            lim = "0"
            for (i = 2; i <= n; i++) {
                if (f[i] ~ /^[0-9]+$/) { lim = f[i]; break }
            }
            b_kbytes[cur] = f[1] + 0
            b_limit[cur]  = lim + 0
            order[++nb]   = cur
            cur = ""
        }
    }
    close(before)

    # --- Parse AFTER ---
    cur = ""
    while ((getline line < after) > 0) {
        if (line ~ /^[[:space:]]*(fscronos-[A-Za-z0-9_]+)/) {
            match(line, /fscronos-[A-Za-z0-9_]+/)
            cur = substr(line, RSTART, RLENGTH)
        } else if (cur != "" && line ~ /^[[:space:]]+[0-9]/) {
            n = split(line, f)
            gsub(/\*/, "", f[1])
            lim = "0"
            for (i = 2; i <= n; i++) {
                if (f[i] ~ /^[0-9]+$/) { lim = f[i]; break }
            }
            a_kbytes[cur] = f[1] + 0
            a_limit[cur]  = lim + 0
            cur = ""
        }
    }
    close(after)

    # --- Header ---
    L = "══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════"
    print ""
    print BOLD "╔" L "╗" NC
    print BOLD "║   COMPARAISON QUOTA LFS  —  avant vs après force_reint  (valeurs en Go)                                      ║" NC
    print BOLD "╠" L "╣" NC
    printf BOLD "║ %-28s │ %12s │ %14s │ %14s │ %14s ║\n" NC, \
        "Filesystem", "Go utilise", "limit av. (Go)", "limit ap. (Go)", "Δ limit (Go)"
    print BOLD "╠" L "╣" NC

    changed = 0; unchanged = 0; flagged = 0

    for (i = 1; i <= nb; i++) {
        fs = order[i]
        bk = b_kbytes[fs]; bl = b_limit[fs]
        ak = a_kbytes[fs]; al = a_limit[fs]

        if (!(fs in a_kbytes)) {
            printf "║ %-28s │ %12s │ %14s │ %14s │ %14s ║\n", \
                fs, kb2gb(bk), kb2gb(bl), "N/A", "N/A"
            continue
        }

        delta_kb = al - bl
        delta_gb = delta_kb / 1048576

        if (delta_kb > 0) {
            delta_str = "+" sprintf("%.2f", delta_gb)
            color = GREEN; changed++
        } else if (delta_kb < 0) {
            delta_str = sprintf("%.2f", delta_gb)
            color = RED; changed++
        } else {
            delta_str = "="
            color = NC; unchanged++
        }

        flag = ""
        if (al > 0 && ak >= al) { flag = " (sature)"; flagged++ }

        printf "║ %-28s │ %12s │ %14s │ %14s │ %s%14s%s ║\n", \
            fs, kb2gb(bk), kb2gb(bl), kb2gb(al), color, delta_str flag, NC
    }

    print BOLD "╚" L "╝" NC
    print ""
    print BOLD "Resume :" NC
    printf "  Entrees avec limit modifiee  : %s%s%d%s\n", BOLD, GREEN, changed, NC
    printf "  Entrees inchangees           : %d\n", unchanged
    if (flagged > 0)
        printf "  %s%s(sature) OSTs satures (utilise >= limit) : %d%s\n", BOLD, YELLOW, flagged, NC
    print ""
}
' /dev/null

total_before_kb=$(grep "Total allocated" "$BEFORE" | grep -oE 'block limit: [0-9]+' | grep -oE '[0-9]+$')
total_after_kb=$(grep  "Total allocated" "$AFTER"  | grep -oE 'block limit: [0-9]+' | grep -oE '[0-9]+$')

to_gb() { echo "$1" | awk '{printf "%.2f", $1/1048576}'; }

echo "  Total allocated block limit avant : $(to_gb $total_before_kb) Go"
echo "  Total allocated block limit après : $(to_gb $total_after_kb) Go"

if [[ -n "$total_before_kb" && -n "$total_after_kb" ]]; then
    delta_gb=$(awk "BEGIN {printf \"%.2f\", ($total_after_kb - $total_before_kb)/1048576}")
    sign=$(echo "$delta_gb" | grep -c '^-' || true)
    if [[ "$sign" -gt 0 ]]; then
        printf "  Delta total                       : \033[0;31m%s Go\033[0m\n" "$delta_gb"
    else
        printf "  Delta total                       : \033[0;32m+%s Go\033[0m\n" "$delta_gb"
    fi
fi
echo ""
