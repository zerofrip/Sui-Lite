#!/system/bin/sh
# service.sh — Sui-Lite (system_shizuku Magisk adaptation)
#
# Executed by Magisk during the late_start service phase (after boot).
# Corresponds to the "on boot → start shizuku" trigger in the original
# init.system_shizuku.rc.
#
# This script performs ONLY:
#   1. Service status verification
#   2. Binder registration check
#   3. SELinux context observation
#   4. Post-activation context capture
#   5. Denial log capture
#
# It does NOT modify SELinux policy, inject rules, or alter system state.
# All policy decisions are left to the operator.

MODDIR=${0%/*}
LOGDIR="/data/local/tmp/sui-lite"
LOGFILE="$LOGDIR/service.log"

mkdir -p "$LOGDIR"

log() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') [service] $1"
    echo "$msg" >> "$LOGFILE"
    log -p i -t "Sui-Lite" "service: $1" 2>/dev/null
}

log "=== service phase START ==="
log "MODDIR=$MODDIR"

# ── 1. SELinux mode ─────────────────────────────────────────────────────
SE_MODE=$(getenforce 2>/dev/null || echo 'unknown')
log "SELinux mode: $SE_MODE"

if [ "$SE_MODE" = "Enforcing" ]; then
    log "NOTE: Running under Enforcing. AVC denials are expected if no"
    log "      custom policy has been loaded for the system_shizuku domain."
fi

# ── 2. init service status ──────────────────────────────────────────────
# The original init.system_shizuku.rc defines a service named "shizuku"
SVC_STATE=$(getprop init.svc.shizuku 2>/dev/null)
if [ "$SVC_STATE" = "running" ]; then
    log "init service 'shizuku': RUNNING"

    # Capture the process domain
    PID=$(getprop init.svc_debug_pid.shizuku 2>/dev/null)
    if [ -z "$PID" ]; then
        PID=$(pidof com.android.systemshizuku 2>/dev/null | awk '{print $1}')
    fi
    if [ -n "$PID" ]; then
        PROC_CTX=$(cat /proc/$PID/attr/current 2>/dev/null || echo 'unreadable')
        log "  PID=$PID  domain=$PROC_CTX"
    else
        log "  PID: not found"
    fi
else
    log "init service 'shizuku': NOT RUNNING (state=${SVC_STATE:-unset})"
    log "  Expected: started by init.system_shizuku.rc via overlay"
    log "  If missing: ensure SystemShizuku.apk is placed in"
    log "  overlay/system/priv-app/SystemShizuku/SystemShizuku.apk"
fi

# ── 3. Binder service registration ──────────────────────────────────────
for svc_name in shizuku system_shizuku shizuku_mgr; do
    if service list 2>/dev/null | grep -q "$svc_name"; then
        log "Binder service '$svc_name': REGISTERED"
    else
        log "Binder service '$svc_name': NOT REGISTERED"
    fi
done

# ── 4. Overlay visibility check ─────────────────────────────────────────
for path in \
    "/system/etc/permissions/com.android.systemshizuku.xml" \
    "/system/etc/permissions/privapp-permissions-systemshizuku.xml" \
    "/system/etc/init/init.system_shizuku.rc" \
    "/system/priv-app/SystemShizuku"
do
    if [ -e "$path" ]; then
        ctx=$(ls -Zd "$path" 2>/dev/null | awk '{print $1}')
        log "VISIBLE: $path  context=$ctx"
    else
        log "NOT VISIBLE: $path"
    fi
done

# ── 5. Post-activation context capture ──────────────────────────────────
if [ -x "$MODDIR/audit/scripts/capture_contexts.sh" ]; then
    log "Running post-activation context capture..."
    sh "$MODDIR/audit/scripts/capture_contexts.sh" "after" "$LOGDIR" 2>>"$LOGFILE"
    log "Post-activation capture: $LOGDIR/contexts.after.txt"
fi

# ── 6. Denial capture ──────────────────────────────────────────────────
if [ -x "$MODDIR/audit/scripts/capture_denials.sh" ]; then
    log "Running AVC denial capture..."
    sh "$MODDIR/audit/scripts/capture_denials.sh" "$LOGDIR" 2>>"$LOGFILE"
    log "Denial capture: $LOGDIR/denials.log"
fi

# ── 7. Domain verification ─────────────────────────────────────────────
if [ -x "$MODDIR/audit/scripts/verify_domains.sh" ]; then
    log "Running domain verification..."
    sh "$MODDIR/audit/scripts/verify_domains.sh" "$LOGDIR" 2>>"$LOGFILE"
    log "Domain map: $LOGDIR/domain.map"
fi

log "=== service phase END ==="
log "Full audit output: $LOGDIR/"
