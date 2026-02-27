#!/system/bin/sh
# capture_denials.sh — Sui-Lite SELinux audit
#
# Captures AVC denial messages related to system_shizuku from the kernel
# audit log and dmesg.
#
# Called with one argument:
#   $1 = output directory
#
# Output: $1/denials.log
#
# This script is a read-only observer. It does NOT modify any state.

OUTDIR="${1:-/data/local/tmp/sui-lite}"
OUTFILE="$OUTDIR/denials.log"

mkdir -p "$OUTDIR"

{
    echo "# Sui-Lite AVC Denial Capture"
    echo "# Timestamp: $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "# SELinux mode: $(getenforce 2>/dev/null || echo 'unknown')"
    echo "#"
    echo "# Source: dmesg + logcat audit"
    echo "# Filter: system_shizuku, shizuku, SystemShizuku"
    echo "# ──────────────────────────────────────────────────────────"
    echo ""

    echo "## dmesg AVC denials (system_shizuku related)"
    echo ""
    # Search dmesg for AVC denials mentioning system_shizuku domains/types
    dmesg 2>/dev/null | grep -iE "avc.*denied" | grep -iE "system_shizuku|shizuku" || \
        echo "(no system_shizuku-related AVC denials found in dmesg)"

    echo ""
    echo "## dmesg AVC denials (all, last 50)"
    echo ""
    dmesg 2>/dev/null | grep -iE "avc.*denied" | tail -50 || \
        echo "(no AVC denials found in dmesg)"

    echo ""
    echo "## logcat audit denials (system_shizuku related)"
    echo ""
    # Attempt to capture from logcat audit buffer
    # Note: this only works if accessible; may require root
    logcat -d -b events -s auditd 2>/dev/null | grep -iE "system_shizuku|shizuku" | tail -50 || \
        echo "(no system_shizuku-related entries in logcat audit buffer)"

    echo ""
    echo "## Kernel audit log (/proc/kmsg snapshot)"
    echo ""
    # On some devices, /proc/last_kmsg or audit.log may be available
    if [ -f "/data/misc/audit/audit.log" ]; then
        grep -iE "system_shizuku|shizuku" /data/misc/audit/audit.log 2>/dev/null | tail -100 || \
            echo "(no matches in audit.log)"
    else
        echo "(/data/misc/audit/audit.log not available)"
    fi

    echo ""
    echo "# ──────────────────────────────────────────────────────────"
    echo "# To capture live denials, run on the device:"
    echo "#   dmesg -w | grep -i 'avc.*denied'"
    echo "#   or:"
    echo "#   logcat -b all | grep -i 'avc.*denied'"
    echo "# ──────────────────────────────────────────────────────────"
    echo "# End of denial capture"
} > "$OUTFILE" 2>&1

echo "Denial capture written to: $OUTFILE"
