#!/system/bin/sh
# post-fs-data.sh — Sui-Lite (system_shizuku Magisk adaptation)
#
# Executed by Magisk during the post-fs-data phase, BEFORE Zygote starts.
# Purpose: Ensure overlay files (permissions XML, init.rc) are visible in
# /system before any service or package scanning begins.
#
# This script performs ONLY:
#   1. Overlay existence verification
#   2. Debug logging
#
# It does NOT modify SELinux policy, set contexts, or alter any state.
# All behavior observation is deferred to audit/scripts/*.

MODDIR=${0%/*}
LOGDIR="/data/local/tmp/sui-lite"
LOGFILE="$LOGDIR/post-fs-data.log"

mkdir -p "$LOGDIR"

log() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') [post-fs-data] $1"
    echo "$msg" >> "$LOGFILE"
    log -p i -t "Sui-Lite" "post-fs-data: $1" 2>/dev/null
}

log "=== post-fs-data phase START ==="
log "MODDIR=$MODDIR"
log "SELinux mode: $(getenforce 2>/dev/null || echo 'unknown')"

# Verify overlay structure
for path in \
    "$MODDIR/overlay/system/etc/permissions/com.android.systemshizuku.xml" \
    "$MODDIR/overlay/system/etc/permissions/privapp-permissions-systemshizuku.xml" \
    "$MODDIR/overlay/system/etc/init/init.system_shizuku.rc" \
    "$MODDIR/overlay/system/priv-app/SystemShizuku"
do
    if [ -e "$path" ]; then
        ctx=$(ls -Z "$path" 2>/dev/null | awk '{print $1}')
        log "OVERLAY OK: $path  context=$ctx"
    else
        log "OVERLAY MISSING: $path"
    fi
done

# Capture pre-activation SELinux file contexts for overlay paths
# (this runs before Magisk magic mount is fully effective)
if [ -x "$MODDIR/audit/scripts/capture_contexts.sh" ]; then
    log "Running pre-activation context capture..."
    sh "$MODDIR/audit/scripts/capture_contexts.sh" "before" "$LOGDIR" 2>>"$LOGFILE"
    log "Pre-activation capture complete: $LOGDIR/contexts.before.txt"
fi

log "=== post-fs-data phase END ==="
