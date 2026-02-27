#!/bin/sh
# build.sh — Compile binder-service.jar for Sui-Lite
#
# Builds a DEX-containing JAR that can be launched via app_process:
#   /system/bin/app_process -Djava.class.path=binder-service.jar \
#       /system/bin com.suilite.binder.BinderEntryPoint
#
# Requirements:
#   - Android SDK (ANDROID_HOME set)
#   - framework-stub.jar (for hidden API: ServiceManager, etc.)
#   - JDK 11+
#
# Usage:
#   ./binder-service/build.sh
#
# Output:
#   binder-service/binder-service.jar (DEX)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_OUT="$SCRIPT_DIR/out"
SRC_DIR="$SCRIPT_DIR/src"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { printf "${CYAN}[binder-build]${NC} %s\n" "$1"; }
ok()   { printf "${GREEN}[  OK  ]${NC} %s\n" "$1"; }
err()  { printf "${RED}[ FAIL ]${NC} %s\n" "$1"; }

log "=== Binder Service Build ==="
log ""

# ── 1. Resolve tools ───────────────────────────────────────────────
ANDROID_HOME="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"

if [ -z "$ANDROID_HOME" ]; then
    err "ANDROID_HOME or ANDROID_SDK_ROOT must be set"
    exit 1
fi

# Find build tools
BT_DIR=$(find "$ANDROID_HOME/build-tools" -maxdepth 1 -type d 2>/dev/null \
    | sort -V | tail -1)
D8="${BT_DIR}/d8"

if [ ! -x "$D8" ]; then
    err "d8 not found in $ANDROID_HOME/build-tools"
    exit 1
fi
log "d8: $D8"

# android.jar for bootclasspath
ANDROID_JAR=$(find "$ANDROID_HOME/platforms" -name "android.jar" 2>/dev/null \
    | sort -V | tail -1)
if [ -z "$ANDROID_JAR" ]; then
    err "android.jar not found in $ANDROID_HOME/platforms"
    exit 1
fi
log "android.jar: $ANDROID_JAR"

# Framework stub for hidden APIs (ServiceManager)
FRAMEWORK_STUB="$MODULE_DIR/build/framework-stub.jar"
if [ ! -f "$FRAMEWORK_STUB" ]; then
    err "Framework stub not found: $FRAMEWORK_STUB"
    err "Extract from device: adb pull /system/framework/framework.jar build/framework-stub.jar"
    exit 1
fi
log "framework stub: $FRAMEWORK_STUB"

# ── 2. Compile Java ───────────────────────────────────────────────
log "Compiling Java sources..."
mkdir -p "$BUILD_OUT/classes"

JAVA_SRCS=$(find "$SRC_DIR" -name "*.java")
SRC_COUNT=$(echo "$JAVA_SRCS" | wc -w)
log "  $SRC_COUNT source files"

# shellcheck disable=SC2086
javac \
    -source 11 -target 11 \
    -classpath "$ANDROID_JAR:$FRAMEWORK_STUB" \
    -bootclasspath "$ANDROID_JAR" \
    -d "$BUILD_OUT/classes" \
    $JAVA_SRCS 2>&1

ok "Java compilation complete"

# ── 3. DEX ─────────────────────────────────────────────────────────
log "Converting to DEX..."
CLASS_FILES=$(find "$BUILD_OUT/classes" -name "*.class")

# shellcheck disable=SC2086
"$D8" \
    --lib "$ANDROID_JAR" \
    --output "$BUILD_OUT" \
    $CLASS_FILES 2>&1

ok "DEX: $BUILD_OUT/classes.dex"

# ── 4. Package JAR ────────────────────────────────────────────────
log "Packaging binder-service.jar..."
OUTPUT_JAR="$SCRIPT_DIR/binder-service.jar"

cd "$BUILD_OUT"
zip -j "$OUTPUT_JAR" classes.dex 2>&1
cd "$MODULE_DIR"

ok "Output: $OUTPUT_JAR"

# ── 5. Record manifest ────────────────────────────────────────────
{
    echo "# Binder Service Build Manifest"
    echo "# Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "jar=$OUTPUT_JAR"
    echo "jar_sha256=$(sha256sum "$OUTPUT_JAR" | awk '{print $1}')"
    echo "jar_size=$(wc -c < "$OUTPUT_JAR")"
    echo "entry_point=com.suilite.binder.BinderEntryPoint"
    echo "service_name=sui_lite_binder"
    echo "src_files=$SRC_COUNT"
} > "$SCRIPT_DIR/build_manifest.txt"

ok "Manifest: $SCRIPT_DIR/build_manifest.txt"
log ""
log "To test on device:"
log "  adb push binder-service/binder-service.jar /data/local/tmp/"
log "  adb shell /system/bin/app_process \\"
log "    -Djava.class.path=/data/local/tmp/binder-service.jar \\"
log "    /system/bin com.suilite.binder.BinderEntryPoint"
