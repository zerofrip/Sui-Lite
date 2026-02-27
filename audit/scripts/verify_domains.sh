#!/system/bin/sh
# verify_domains.sh — Sui-Lite SELinux audit
#
# Verifies that runtime process domains and file contexts match the
# expectations defined in the upstream system_shizuku SELinux policy.
#
# Called with one argument:
#   $1 = output directory
#
# Output: $1/domain.map
#
# This script is a read-only observer. It does NOT modify any state.

OUTDIR="${1:-/data/local/tmp/sui-lite}"
OUTFILE="$OUTDIR/domain.map"

mkdir -p "$OUTDIR"

PASS=0
FAIL=0
SKIP=0

check() {
    local desc="$1"
    local actual="$2"
    local expected="$3"

    if [ -z "$actual" ] || [ "$actual" = "unreadable" ] || [ "$actual" = "<not_found>" ]; then
        echo "  SKIP  $desc"
        echo "        actual:   (not available)"
        echo "        expected: $expected"
        SKIP=$((SKIP + 1))
    elif echo "$actual" | grep -q "$expected"; then
        echo "  PASS  $desc"
        echo "        actual:   $actual"
        echo "        expected: $expected"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $desc"
        echo "        actual:   $actual"
        echo "        expected: $expected"
        FAIL=$((FAIL + 1))
    fi
    echo ""
}

{
    echo "# Sui-Lite Domain & Context Verification"
    echo "# Timestamp: $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "# SELinux mode: $(getenforce 2>/dev/null || echo 'unknown')"
    echo "#"
    echo "# Verifies runtime state against upstream SELinux policy expectations"
    echo "# Source: upstream/system_shizuku/sepolicy/"
    echo "# ──────────────────────────────────────────────────────────"
    echo ""

    # ── Process Domain Checks ───────────────────────────────────────────
    echo "## Process Domain Checks"
    echo ""
    echo "# Expected: system_shizuku service runs in domain u:r:system_shizuku:s0"
    echo "# Source: init.system_shizuku.rc line: seclabel u:r:system_shizuku:s0"
    echo ""

    # Find the shizuku process
    SHIZUKU_PID=""
    for procname in shizuku com.android.systemshizuku; do
        pids=$(pidof "$procname" 2>/dev/null)
        if [ -n "$pids" ]; then
            SHIZUKU_PID=$(echo "$pids" | awk '{print $1}')
            break
        fi
    done

    if [ -n "$SHIZUKU_PID" ]; then
        PROC_CTX=$(cat /proc/$SHIZUKU_PID/attr/current 2>/dev/null || echo 'unreadable')
        check "shizuku process domain (PID=$SHIZUKU_PID)" "$PROC_CTX" "system_shizuku"
    else
        echo "  SKIP  shizuku process domain"
        echo "        (process not running)"
        echo ""
        SKIP=$((SKIP + 1))
    fi

    # ── File Context Checks ─────────────────────────────────────────────
    echo "## File Context Checks"
    echo ""
    echo "# Expected contexts from upstream sepolicy/file_contexts:"
    echo "#   /system/priv-app/SystemShizuku(/.*)?  u:object_r:system_file:s0"
    echo "#   /system/bin/system_shizuku            u:object_r:system_shizuku_exec:s0"
    echo "#   /data/system/system_shizuku(/.*)?     u:object_r:system_shizuku_data_file:s0"
    echo ""

    # priv-app directory
    if [ -d "/system/priv-app/SystemShizuku" ]; then
        ctx=$(ls -Zd /system/priv-app/SystemShizuku 2>/dev/null | awk '{print $1}')
        check "/system/priv-app/SystemShizuku" "$ctx" "system_file"
    else
        echo "  SKIP  /system/priv-app/SystemShizuku"
        echo "        (path does not exist)"
        echo ""
        SKIP=$((SKIP + 1))
    fi

    # Data directory
    if [ -d "/data/system/system_shizuku" ]; then
        ctx=$(ls -Zd /data/system/system_shizuku 2>/dev/null | awk '{print $1}')
        check "/data/system/system_shizuku" "$ctx" "system_shizuku_data_file"
    else
        echo "  SKIP  /data/system/system_shizuku"
        echo "        (path does not exist — service may not have run yet)"
        echo ""
        SKIP=$((SKIP + 1))
    fi

    # ── Service Context Checks ──────────────────────────────────────────
    echo "## Service Context Checks"
    echo ""
    echo "# Expected from upstream sepolicy/service_contexts:"
    echo "#   shizuku            u:object_r:system_shizuku_service:s0"
    echo "#   system_shizuku     u:object_r:system_shizuku_service:s0"
    echo "#   shizuku_mgr        u:object_r:system_shizuku_mgr_service:s0"
    echo ""

    # Check if services are registered
    for svc in shizuku system_shizuku shizuku_mgr; do
        if service list 2>/dev/null | grep -q "$svc"; then
            echo "  PASS  Binder service '$svc' is registered"
        else
            echo "  FAIL  Binder service '$svc' is NOT registered"
            FAIL=$((FAIL + 1))
        fi
    done
    echo ""

    # ── Permission XML Checks ───────────────────────────────────────────
    echo "## Permission XML Overlay Checks"
    echo ""

    for xml in \
        /system/etc/permissions/com.android.systemshizuku.xml \
        /system/etc/permissions/privapp-permissions-systemshizuku.xml
    do
        if [ -f "$xml" ]; then
            ctx=$(ls -Z "$xml" 2>/dev/null | awk '{print $1}')
            check "$xml" "$ctx" "system_file"
        else
            echo "  SKIP  $xml"
            echo "        (not found — overlay may not be active)"
            echo ""
            SKIP=$((SKIP + 1))
        fi
    done

    # ── init.rc Overlay Check ───────────────────────────────────────────
    echo "## init.rc Overlay Check"
    echo ""
    INITRC="/system/etc/init/init.system_shizuku.rc"
    if [ -f "$INITRC" ]; then
        ctx=$(ls -Z "$INITRC" 2>/dev/null | awk '{print $1}')
        check "$INITRC" "$ctx" "system_file"
    else
        echo "  SKIP  $INITRC"
        echo "        (not found — overlay may not be active)"
        echo ""
        SKIP=$((SKIP + 1))
    fi

    # ── Summary ─────────────────────────────────────────────────────────
    echo "# ──────────────────────────────────────────────────────────"
    echo "# SUMMARY"
    echo "#   PASS: $PASS"
    echo "#   FAIL: $FAIL"
    echo "#   SKIP: $SKIP"
    echo "# ──────────────────────────────────────────────────────────"
    echo "#"
    echo "# FAILs indicate domain/context mismatches that may require"
    echo "# SELinux policy adjustments OUTSIDE this module."
    echo "#"
    echo "# SKIPs indicate components that are not yet active or"
    echo "# not yet installed."
    echo "# ──────────────────────────────────────────────────────────"
    echo "# End of domain verification"
} > "$OUTFILE" 2>&1

echo "Domain verification written to: $OUTFILE"
echo "Results: PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
