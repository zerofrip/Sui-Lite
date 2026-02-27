#!/bin/sh
# env_check.sh — Sui-Lite build environment validation
#
# Validates that the host machine has the required tools to build
# SystemShizuku from upstream sources.
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more required tools missing
#
# Usage:
#   ./build/env_check.sh [--aosp | --standalone]
#
# This script is a read-only diagnostic. It does NOT install anything.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UPSTREAM_DIR="$MODULE_DIR/upstream/system_shizuku"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { printf "${GREEN}  PASS${NC}  %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "${RED}  FAIL${NC}  %s\n" "$1"; FAIL=$((FAIL + 1)); }
warn() { printf "${YELLOW}  WARN${NC}  %s\n" "$1"; WARN=$((WARN + 1)); }

check_cmd() {
    if command -v "$1" >/dev/null 2>&1; then
        ver=$("$1" --version 2>/dev/null | head -1 || echo "version unknown")
        pass "$1 found: $ver"
    else
        fail "$1 not found"
    fi
}

check_file() {
    if [ -f "$1" ]; then
        pass "$1 exists"
    else
        fail "$1 missing"
    fi
}

check_dir() {
    if [ -d "$1" ]; then
        pass "$1 exists"
    else
        fail "$1 missing"
    fi
}

# ──────────────────────────────────────────────────────────────────────
echo "╔══════════════════════════════════════════════════════╗"
echo "║  Sui-Lite Build Environment Check                   ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

MODE="${1:-auto}"
echo "Mode: $MODE"
echo ""

# ── 1. Upstream source presence ─────────────────────────────────────
echo "── Upstream Source ──"
check_dir "$UPSTREAM_DIR"
check_file "$UPSTREAM_DIR/Android.bp"
check_file "$UPSTREAM_DIR/service/AndroidManifest.xml"
check_dir "$UPSTREAM_DIR/service/src"
check_dir "$UPSTREAM_DIR/aidl"
echo ""

# ── 2. General build tools ──────────────────────────────────────────
echo "── General Build Tools ──"
check_cmd "java"
check_cmd "javac"

# Java version check (need 11+ for AOSP, 17+ for modern Gradle)
JAVA_VER=$(java -version 2>&1 | head -1 | sed -E 's/.*"([0-9]+).*/\1/')
if [ -n "$JAVA_VER" ] && [ "$JAVA_VER" -ge 11 ] 2>/dev/null; then
    pass "Java version $JAVA_VER (>= 11)"
else
    warn "Java version $JAVA_VER may be too old (need >= 11)"
fi

check_cmd "aapt2"
check_cmd "d8"
check_cmd "zip"
check_cmd "unzip"
check_cmd "sha256sum"
echo ""

# ── 3. Android SDK / Build Tools ────────────────────────────────────
echo "── Android SDK ──"
if [ -n "$ANDROID_HOME" ] && [ -d "$ANDROID_HOME" ]; then
    pass "ANDROID_HOME=$ANDROID_HOME"
elif [ -n "$ANDROID_SDK_ROOT" ] && [ -d "$ANDROID_SDK_ROOT" ]; then
    pass "ANDROID_SDK_ROOT=$ANDROID_SDK_ROOT"
else
    warn "ANDROID_HOME / ANDROID_SDK_ROOT not set"
fi

# Look for build-tools
if command -v aapt2 >/dev/null 2>&1; then
    pass "aapt2 available on PATH"
elif [ -n "$ANDROID_HOME" ]; then
    BT=$(find "$ANDROID_HOME/build-tools" -name "aapt2" 2>/dev/null | sort -V | tail -1)
    if [ -n "$BT" ]; then
        pass "aapt2 found at: $BT"
    else
        fail "aapt2 not found in ANDROID_HOME/build-tools"
    fi
fi

# Look for android.jar (compile SDK)
if [ -n "$ANDROID_HOME" ]; then
    ANDROID_JAR=$(find "$ANDROID_HOME/platforms" -name "android.jar" 2>/dev/null | sort -V | tail -1)
    if [ -n "$ANDROID_JAR" ]; then
        pass "android.jar: $ANDROID_JAR"
    else
        warn "android.jar not found (needed for standalone build)"
    fi
fi
echo ""

# ── 4. AOSP tree detection ──────────────────────────────────────────
echo "── AOSP Tree (optional) ──"
if [ -n "$ANDROID_BUILD_TOP" ] && [ -d "$ANDROID_BUILD_TOP" ]; then
    pass "ANDROID_BUILD_TOP=$ANDROID_BUILD_TOP"
    if [ -f "$ANDROID_BUILD_TOP/build/soong/soong_ui.bash" ]; then
        pass "Soong build system found"
    else
        fail "Soong build system not found at ANDROID_BUILD_TOP"
    fi
else
    warn "ANDROID_BUILD_TOP not set (AOSP tree build unavailable)"
    warn "Standalone build mode will be used"
fi
echo ""

# ── 5. Signing tools ───────────────────────────────────────────────
echo "── Signing ──"
check_cmd "apksigner"
check_cmd "keytool"

# Check for debug keystore
DEBUG_KEY="$HOME/.android/debug.keystore"
if [ -f "$DEBUG_KEY" ]; then
    pass "Debug keystore: $DEBUG_KEY"
else
    warn "Debug keystore not found (will be created during build)"
fi
echo ""

# ── 6. Framework stub (standalone build) ────────────────────────────
echo "── Framework Stub (standalone build) ──"
FRAMEWORK_STUB="$MODULE_DIR/build/framework-stub.jar"
if [ -f "$FRAMEWORK_STUB" ]; then
    pass "Framework stub: $FRAMEWORK_STUB"
else
    warn "Framework stub not found at: $FRAMEWORK_STUB"
    warn "The upstream code uses hidden platform APIs."
    warn "For standalone builds, you must extract framework.jar from your device:"
    warn "  adb pull /system/framework/framework.jar build/framework-stub.jar"
    warn "This provides the hidden API stubs needed for compilation."
fi
echo ""

# ── Summary ─────────────────────────────────────────────────────────
echo "══════════════════════════════════════════════════════"
printf "  Results:  ${GREEN}PASS=%d${NC}  ${RED}FAIL=%d${NC}  ${YELLOW}WARN=%d${NC}\n" \
    "$PASS" "$FAIL" "$WARN"
echo "══════════════════════════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "Some required tools are missing. See README.build.md for setup instructions."
    exit 1
else
    echo ""
    echo "Environment is ready to build."
    exit 0
fi
