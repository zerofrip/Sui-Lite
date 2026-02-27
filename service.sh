#!/system/bin/sh
# service.sh — Sui-Lite (system_shizuku Magisk adaptation)
#
# Executed by Magisk during the late_start service phase (after boot).
# Corresponds to the "on boot → start shizuku" trigger in the original
# init.system_shizuku.rc.
#
# This script performs:
#   1. Service status verification
#   2. Binder registration check (upstream services)
#   3. Sui-Lite Binder service launch (via app_process)
#   4. SELinux context observation
#   5. Post-activation context capture
#   6. Denial log capture
#   7. Binder context audit
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

# ── 3. Upstream Binder service registration ─────────────────────────────
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

# ── 5. Sui-Lite Binder service launch ──────────────────────────────────
# Launch our custom Binder service via app_process.
# This runs as a background process under the current UID (root from Magisk).
# SELinux domain depends on transition rules — denials are captured.
BINDER_JAR="$MODDIR/binder-service/binder-service.jar"
BINDER_ENTRY="com.suilite.binder.BinderEntryPoint"
BINDER_SERVICE_NAME="sui_lite_binder"

if [ -f "$BINDER_JAR" ]; then
    log "Binder JAR found: $BINDER_JAR"

    # Wait for system services to be ready before launching.
    # The service needs ServiceManager to be fully operational.
    log "Waiting for system_server readiness..."
    WAIT_COUNT=0
    MAX_WAIT=30
    while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
        # Check if system_server is running and ServiceManager is responsive
        if service list >/dev/null 2>&1; then
            log "ServiceManager is responsive (waited ${WAIT_COUNT}s)"
            break
        fi
        sleep 1
        WAIT_COUNT=$((WAIT_COUNT + 1))
    done

    if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
        log "WARN: ServiceManager not responsive after ${MAX_WAIT}s"
        log "  Proceeding anyway — Binder registration may fail"
    fi

    # Wait for Shizuku framework readiness (if upstream services are available)
    SHIZUKU_WAIT=0
    SHIZUKU_MAX=15
    while [ $SHIZUKU_WAIT -lt $SHIZUKU_MAX ]; do
        if service list 2>/dev/null | grep -q "shizuku\|system_shizuku"; then
            log "Shizuku service detected (waited ${SHIZUKU_WAIT}s)"
            break
        fi
        sleep 1
        SHIZUKU_WAIT=$((SHIZUKU_WAIT + 1))
    done

    if [ $SHIZUKU_WAIT -ge $SHIZUKU_MAX ]; then
        log "NOTE: No Shizuku service detected after ${SHIZUKU_MAX}s"
        log "  This is expected if SystemShizuku.apk is not installed."
        log "  Proceeding with Binder service launch anyway."
    fi

    # Kill any existing instance to avoid duplicate registration
    OLD_PID=$(pidof "$BINDER_ENTRY" 2>/dev/null)
    if [ -n "$OLD_PID" ]; then
        log "Killing existing Binder service PID=$OLD_PID"
        kill "$OLD_PID" 2>/dev/null
        sleep 1
    fi

    # Launch via app_process
    # - Runs in background (&) so service.sh can continue
    # - Stdout/stderr redirected to log file for debugging
    # - CLASSPATH set via -D flag as required by app_process
    log "Launching Binder service..."
    log "  JAR: $BINDER_JAR"
    log "  Entry: $BINDER_ENTRY"
    log "  UID: $(id -u)"
    log "  SELinux: $(cat /proc/self/attr/current 2>/dev/null || echo unknown)"

    /system/bin/app_process \
        -Djava.class.path="$BINDER_JAR" \
        /system/bin \
        "$BINDER_ENTRY" \
        >> "$LOGDIR/binder_service.log" 2>&1 &

    BINDER_PID=$!
    log "Binder service launched: PID=$BINDER_PID"

    # Give the service time to register
    sleep 2

    # Check if it's still alive
    if kill -0 "$BINDER_PID" 2>/dev/null; then
        BINDER_CTX=$(cat "/proc/$BINDER_PID/attr/current" 2>/dev/null || echo "unreadable")
        log "Binder service alive: PID=$BINDER_PID domain=$BINDER_CTX"
    else
        log "WARN: Binder service exited shortly after launch"
        log "  Check $LOGDIR/binder_service.log for details"
    fi

    # Check registration
    if service list 2>/dev/null | grep -q "$BINDER_SERVICE_NAME"; then
        log "Binder service '$BINDER_SERVICE_NAME': REGISTERED"
    else
        log "Binder service '$BINDER_SERVICE_NAME': NOT REGISTERED"
        log "  This is expected under SELinux Enforcing without custom policy."
        log "  The service process remains alive for audit inspection."
    fi
else
    log "Binder JAR not found: $BINDER_JAR"
    log "  Build with: ./binder-service/build.sh"
    log "  Skipping Binder service launch."
fi

# ── 6. Post-activation context capture ──────────────────────────────────
if [ -x "$MODDIR/audit/scripts/capture_contexts.sh" ]; then
    log "Running post-activation context capture..."
    sh "$MODDIR/audit/scripts/capture_contexts.sh" "after" "$LOGDIR" 2>>"$LOGFILE"
    log "Post-activation capture: $LOGDIR/contexts.after.txt"
fi

# ── 7. Denial capture ──────────────────────────────────────────────────
if [ -x "$MODDIR/audit/scripts/capture_denials.sh" ]; then
    log "Running AVC denial capture..."
    sh "$MODDIR/audit/scripts/capture_denials.sh" "$LOGDIR" 2>>"$LOGFILE"
    log "Denial capture: $LOGDIR/denials.log"
fi

# ── 8. Domain verification ─────────────────────────────────────────────
if [ -x "$MODDIR/audit/scripts/verify_domains.sh" ]; then
    log "Running domain verification..."
    sh "$MODDIR/audit/scripts/verify_domains.sh" "$LOGDIR" 2>>"$LOGFILE"
    log "Domain map: $LOGDIR/domain.map"
fi

# ── 9. Binder context audit ───────────────────────────────────────────
if [ -x "$MODDIR/audit/scripts/capture_binder_contexts.sh" ]; then
    log "Running Binder context audit..."
    sh "$MODDIR/audit/scripts/capture_binder_contexts.sh" "$LOGDIR" 2>>"$LOGFILE"
    log "Binder contexts: $LOGDIR/binder_contexts.txt"
fi

log "=== service phase END ==="
log "Full audit output: $LOGDIR/"
