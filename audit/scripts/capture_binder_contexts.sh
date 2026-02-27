#!/system/bin/sh
# capture_binder_contexts.sh — Binder registration SELinux audit
#
# Captures SELinux context and registration status of the
# sui_lite_binder service process after it has been launched.
#
# Usage:
#   sh capture_binder_contexts.sh <output_dir>
#
# Output:
#   <output_dir>/binder_contexts.txt
#
# This script is a read-only observer. It does NOT modify system state.

OUTPUT_DIR="${1:-/data/local/tmp/sui-lite}"
OUTPUT_FILE="$OUTPUT_DIR/binder_contexts.txt"
SERVICE_NAME="sui_lite_binder"
PROCESS_CLASS="com.suilite.binder.BinderEntryPoint"

mkdir -p "$OUTPUT_DIR"

{
    echo "# Sui-Lite Binder Context Capture"
    echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "# Service name: $SERVICE_NAME"
    echo "#"
    echo ""

    # ── 1. Binder service registration ─────────────────────────────
    echo "=== Binder Registration ==="
    if service list 2>/dev/null | grep -q "$SERVICE_NAME"; then
        echo "REGISTERED: $SERVICE_NAME"
        service list 2>/dev/null | grep "$SERVICE_NAME"
    else
        echo "NOT REGISTERED: $SERVICE_NAME"
        echo "  (Expected under SELinux Enforcing without custom policy)"
    fi
    echo ""

    # Also check upstream services for comparison
    echo "=== Upstream Binder Services ==="
    for svc in shizuku system_shizuku shizuku_mgr; do
        if service list 2>/dev/null | grep -q "$svc"; then
            echo "REGISTERED: $svc"
        else
            echo "NOT REGISTERED: $svc"
        fi
    done
    echo ""

    # ── 2. Process domain ──────────────────────────────────────────
    echo "=== Service Process ==="
    PID=$(pidof "$PROCESS_CLASS" 2>/dev/null | awk '{print $1}')
    if [ -n "$PID" ]; then
        PROC_CTX=$(cat "/proc/$PID/attr/current" 2>/dev/null || echo "unreadable")
        PROC_UID=$(stat -c "%u" "/proc/$PID" 2>/dev/null || echo "unknown")
        PROC_GID=$(stat -c "%g" "/proc/$PID" 2>/dev/null || echo "unknown")
        PROC_CMD=$(cat "/proc/$PID/cmdline" 2>/dev/null | tr '\0' ' ' || echo "unknown")

        echo "PID: $PID"
        echo "UID: $PROC_UID"
        echo "GID: $PROC_GID"
        echo "SELinux context: $PROC_CTX"
        echo "Command: $PROC_CMD"

        # Check the exe link
        EXE=$(readlink "/proc/$PID/exe" 2>/dev/null || echo "unreadable")
        echo "Executable: $EXE"
    else
        echo "NOT RUNNING"
        echo "  Process: $PROCESS_CLASS"
    fi
    echo ""

    # ── 3. Binder-related AVC denials ──────────────────────────────
    echo "=== Binder-Related AVC Denials ==="
    if command -v dmesg >/dev/null 2>&1; then
        DENIALS=$(dmesg 2>/dev/null | grep -i 'avc.*denied' | grep -iE 'sui_lite|binder_service|addService' | tail -20)
        if [ -n "$DENIALS" ]; then
            echo "$DENIALS"
        else
            echo "(no sui_lite-specific Binder denials found in dmesg)"
        fi
    fi
    echo ""

    # Also check for ServiceManager add denials (general)
    echo "=== ServiceManager Add Denials ==="
    if command -v dmesg >/dev/null 2>&1; then
        SM_DENIALS=$(dmesg 2>/dev/null | grep -i 'avc.*denied.*add' | grep -i 'servicemanager' | tail -10)
        if [ -n "$SM_DENIALS" ]; then
            echo "$SM_DENIALS"
        else
            echo "(no ServiceManager add denials found)"
        fi
    fi
    echo ""

    # ── 4. JAR file context ────────────────────────────────────────
    echo "=== JAR File Context ==="
    JAR_PATHS="/data/adb/modules/sui-lite/binder-service/binder-service.jar
/data/local/tmp/binder-service.jar"

    for jar in $JAR_PATHS; do
        if [ -f "$jar" ]; then
            CTX=$(ls -Z "$jar" 2>/dev/null | awk '{print $1}')
            SHA=$(sha256sum "$jar" 2>/dev/null | awk '{print $1}')
            echo "PATH: $jar"
            echo "  context: $CTX"
            echo "  sha256: $SHA"
        fi
    done
    echo ""

    echo "# End of Binder context capture"

} > "$OUTPUT_FILE"

echo "Binder contexts captured: $OUTPUT_FILE"
