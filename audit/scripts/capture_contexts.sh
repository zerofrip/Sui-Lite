#!/system/bin/sh
# capture_contexts.sh — Sui-Lite SELinux audit
#
# Captures SELinux file contexts for all paths relevant to system_shizuku.
# Called with two arguments:
#   $1 = phase ("before" or "after")
#   $2 = output directory
#
# Output: $2/contexts.$1.txt
#
# This script is a read-only observer. It does NOT modify any state.

PHASE="${1:-unknown}"
OUTDIR="${2:-/data/local/tmp/sui-lite}"
OUTFILE="$OUTDIR/contexts.${PHASE}.txt"

mkdir -p "$OUTDIR"

{
    echo "# Sui-Lite SELinux Context Capture"
    echo "# Phase: $PHASE"
    echo "# Timestamp: $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "# SELinux mode: $(getenforce 2>/dev/null || echo 'unknown')"
    echo "#"
    echo "# Format: <context>  <path>"
    echo "# ──────────────────────────────────────────────────────────"
    echo ""

    echo "## Overlay paths (expected by system_shizuku)"
    echo ""
    for path in \
        /system/priv-app/SystemShizuku \
        /system/priv-app/SystemShizuku/SystemShizuku.apk \
        /system/etc/permissions/com.android.systemshizuku.xml \
        /system/etc/permissions/privapp-permissions-systemshizuku.xml \
        /system/etc/init/init.system_shizuku.rc
    do
        if [ -e "$path" ]; then
            ctx=$(ls -Zd "$path" 2>/dev/null | awk '{print $1}')
            echo "$ctx  $path"
        else
            echo "<not_found>  $path"
        fi
    done

    echo ""
    echo "## Data paths (runtime state)"
    echo ""
    for path in \
        /data/system/system_shizuku \
        /data/system/system_shizuku/grants_u0.json \
        /data/system/system_shizuku/audit_u0.json
    do
        if [ -e "$path" ]; then
            ctx=$(ls -Zd "$path" 2>/dev/null | awk '{print $1}')
            echo "$ctx  $path"
        else
            echo "<not_found>  $path"
        fi
    done

    echo ""
    echo "## Reference system paths (for context comparison)"
    echo ""
    for path in \
        /system/bin/app_process \
        /system/bin/app_process64 \
        /system/bin/sh \
        /system/priv-app \
        /system/etc/permissions \
        /system/etc/init
    do
        if [ -e "$path" ]; then
            ctx=$(ls -Zd "$path" 2>/dev/null | awk '{print $1}')
            echo "$ctx  $path"
        else
            echo "<not_found>  $path"
        fi
    done

    echo ""
    echo "## Process contexts (running services)"
    echo ""
    # Shizuku service process
    for procname in shizuku com.android.systemshizuku; do
        pids=$(pidof "$procname" 2>/dev/null)
        if [ -n "$pids" ]; then
            for pid in $pids; do
                ctx=$(cat /proc/$pid/attr/current 2>/dev/null || echo 'unreadable')
                echo "$ctx  pid=$pid ($procname)"
            done
        else
            echo "<not_running>  $procname"
        fi
    done

    echo ""
    echo "# ──────────────────────────────────────────────────────────"
    echo "# End of capture: $PHASE"
} > "$OUTFILE" 2>&1

echo "Context capture ($PHASE) written to: $OUTFILE"
