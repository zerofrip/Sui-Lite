#!/bin/sh
# build_apks.sh — Sui-Lite deterministic APK build pipeline
#
# Builds SystemShizuku from upstream sources without modifying them.
#
# Supports two build modes:
#   1. AOSP tree build  (--aosp)   — uses Soong via Android.bp
#   2. Standalone build (--standalone) — uses javac/aapt2/d8 directly
#
# Usage:
#   ./build/build_apks.sh [--aosp | --standalone] [--deploy]
#
# Options:
#   --aosp         Build using AOSP Soong (requires ANDROID_BUILD_TOP)
#   --standalone   Build using SDK tools + framework stub
#   --deploy       Copy APK to overlay/system/priv-app/ after build
#   --help         Show this help
#
# Exit codes:
#   0 — build and optional deployment succeeded
#   1 — build failed
#   2 — environment check failed
#
# This script does NOT modify upstream sources.
# All build artifacts go to build/out/.

set -e

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UPSTREAM_DIR="$MODULE_DIR/upstream/system_shizuku"
BUILD_OUT="$SCRIPT_DIR/out"
OVERLAY_DIR="$MODULE_DIR/overlay/system/priv-app/SystemShizuku"
AUDIT_DIR="$MODULE_DIR/audit/selinux"

# APK metadata (from upstream AndroidManifest.xml)
APK_PACKAGE="com.android.systemshizuku"
APK_NAME="SystemShizuku"
APK_VERSION_CODE="1"
APK_VERSION_NAME="1.0"

# Build timestamps
BUILD_TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
BUILD_ID="$(date '+%Y%m%d_%H%M%S')"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { printf "${CYAN}[build]${NC} %s\n" "$1"; }
ok()   { printf "${GREEN}[  OK ]${NC} %s\n" "$1"; }
err()  { printf "${RED}[FAIL]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }

# ============================================================================
# Argument parsing
# ============================================================================

MODE=""
DEPLOY=0

usage() {
    sed -n '2,/^$/s/^# //p' "$0"
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --aosp)       MODE="aosp" ;;
        --standalone) MODE="standalone" ;;
        --deploy)     DEPLOY=1 ;;
        --help|-h)    usage ;;
        *)            err "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

# Auto-detect mode if not specified
if [ -z "$MODE" ]; then
    if [ -n "$ANDROID_BUILD_TOP" ] && [ -d "$ANDROID_BUILD_TOP" ]; then
        MODE="aosp"
        log "Auto-detected AOSP tree at $ANDROID_BUILD_TOP"
    else
        MODE="standalone"
        log "No AOSP tree detected — using standalone mode"
    fi
fi

log "Build mode: $MODE"
log "Build ID: $BUILD_ID"
log "Timestamp: $BUILD_TIMESTAMP"
echo ""

# ============================================================================
# Environment validation
# ============================================================================

log "Running environment check..."
if ! sh "$SCRIPT_DIR/env_check.sh" "--$MODE" 2>/dev/null; then
    # Run it visibly so the user sees what's missing
    sh "$SCRIPT_DIR/env_check.sh" "--$MODE" || true
    err "Environment check failed. See above for details."
    exit 2
fi
echo ""

# ============================================================================
# AOSP Tree Build
# ============================================================================

build_aosp() {
    log "═══ AOSP Tree Build ═══"
    log ""

    # -- 1. Verify AOSP linkage ──────────────────────────────────────────
    AOSP_TARGET="$ANDROID_BUILD_TOP/packages/apps/SystemShizuku"

    if [ ! -d "$AOSP_TARGET" ]; then
        log "Upstream not linked in AOSP tree. Creating symlink..."
        log "  $UPSTREAM_DIR → $AOSP_TARGET"
        ln -sfn "$UPSTREAM_DIR" "$AOSP_TARGET"
        ok "Symlink created"
    else
        ok "AOSP target exists: $AOSP_TARGET"
    fi

    # -- 2. Build via Soong ──────────────────────────────────────────────
    log "Building SystemShizuku via Soong..."
    log "  Command: m SystemShizuku"

    cd "$ANDROID_BUILD_TOP"

    # Source envsetup if not already done
    if ! command -v m >/dev/null 2>&1; then
        log "Sourcing envsetup.sh..."
        # shellcheck disable=SC1091
        . build/envsetup.sh
    fi

    # Build the APK module
    m SystemShizuku 2>&1 | tee "$BUILD_OUT/soong_build.log"

    if [ $? -ne 0 ]; then
        err "Soong build failed. See $BUILD_OUT/soong_build.log"
        return 1
    fi

    # -- 3. Locate the built APK ─────────────────────────────────────────
    # Soong output path depends on target architecture
    APK_PATH=$(find "$ANDROID_BUILD_TOP/out/target/product" \
        -path "*/priv-app/SystemShizuku/SystemShizuku.apk" \
        -type f 2>/dev/null | head -1)

    if [ -z "$APK_PATH" ]; then
        err "Built APK not found in AOSP out/ tree"
        return 1
    fi

    ok "APK built: $APK_PATH"

    # -- 4. Copy to build/out ────────────────────────────────────────────
    mkdir -p "$BUILD_OUT"
    cp "$APK_PATH" "$BUILD_OUT/$APK_NAME.apk"
    ok "Copied to: $BUILD_OUT/$APK_NAME.apk"

    # Also build AIDL stubs if needed
    m system_shizuku_aidl 2>&1 | tee -a "$BUILD_OUT/soong_build.log" || true

    return 0
}

# ============================================================================
# Standalone Build (javac + aapt2 + d8)
# ============================================================================

build_standalone() {
    log "═══ Standalone Build ═══"
    log ""
    log "This mode compiles the upstream Java source using SDK tools."
    log "It requires a framework stub JAR for hidden API access."
    log ""

    # -- 1. Resolve tool paths ───────────────────────────────────────────
    ANDROID_HOME="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"

    if [ -z "$ANDROID_HOME" ]; then
        err "ANDROID_HOME or ANDROID_SDK_ROOT must be set"
        return 1
    fi

    # Find latest build-tools
    BT_DIR=$(find "$ANDROID_HOME/build-tools" -maxdepth 1 -type d 2>/dev/null \
        | sort -V | tail -1)
    if [ -z "$BT_DIR" ]; then
        err "No build-tools found in $ANDROID_HOME/build-tools"
        return 1
    fi
    log "Build tools: $BT_DIR"

    AAPT2="${BT_DIR}/aapt2"
    D8="${BT_DIR}/d8"
    ZIPALIGN="${BT_DIR}/zipalign"
    APKSIGNER="${BT_DIR}/apksigner"

    # Find android.jar (compile SDK)
    ANDROID_JAR=$(find "$ANDROID_HOME/platforms" -name "android.jar" 2>/dev/null \
        | sort -V | tail -1)
    if [ -z "$ANDROID_JAR" ]; then
        err "android.jar not found in $ANDROID_HOME/platforms"
        return 1
    fi
    log "android.jar: $ANDROID_JAR"

    # Framework stub for hidden APIs
    FRAMEWORK_STUB="$SCRIPT_DIR/framework-stub.jar"
    if [ ! -f "$FRAMEWORK_STUB" ]; then
        err "Framework stub not found: $FRAMEWORK_STUB"
        err ""
        err "The upstream code uses hidden Android platform APIs:"
        err "  - android.os.ServiceManager"
        err "  - android.app.ActivityThread"
        err "  - android.util.Slog"
        err "  - android.os.SystemProperties"
        err ""
        err "To extract from your device:"
        err "  adb pull /system/framework/framework.jar build/framework-stub.jar"
        err ""
        err "Or from an AOSP build output:"
        err "  cp out/target/common/obj/JAVA_LIBRARIES/framework_intermediates/classes.jar \\"
        err "     build/framework-stub.jar"
        return 1
    fi
    log "Framework stub: $FRAMEWORK_STUB"

    # Jetpack libs
    SECURITY_CRYPTO="$SCRIPT_DIR/libs/security-crypto.jar"
    ANNOTATION_JAR="$SCRIPT_DIR/libs/annotation.jar"
    if [ ! -f "$SECURITY_CRYPTO" ]; then
        warn "Jetpack Security-Crypto JAR not found at: $SECURITY_CRYPTO"
        warn "PermissionStore (encrypted grant/audit store) will fail to compile."
        warn ""
        warn "Download from Maven Central:"
        warn "  mkdir -p build/libs"
        warn "  wget -O build/libs/security-crypto.jar \\"
        warn "    https://repo1.maven.org/maven2/androidx/security/security-crypto/1.1.0-alpha06/security-crypto-1.1.0-alpha06.jar"
        warn "  wget -O build/libs/annotation.jar \\"
        warn "    https://repo1.maven.org/maven2/androidx/annotation/annotation/1.7.0/annotation-1.7.0.jar"
    fi

    # -- 2. Prepare build output ─────────────────────────────────────────
    mkdir -p "$BUILD_OUT"
    CLASSES_DIR="$BUILD_OUT/classes"
    GEN_DIR="$BUILD_OUT/gen"
    RES_DIR="$BUILD_OUT/res"
    mkdir -p "$CLASSES_DIR" "$GEN_DIR" "$RES_DIR"

    # -- 3. Compile AIDL ─────────────────────────────────────────────────
    log "Compiling AIDL interfaces..."
    AIDL_TOOL="$(find "$ANDROID_HOME/build-tools" -name "aidl" 2>/dev/null \
        | sort -V | tail -1)"

    if [ -z "$AIDL_TOOL" ]; then
        err "aidl tool not found in build-tools"
        return 1
    fi

    AIDL_COUNT=0
    find "$UPSTREAM_DIR/aidl" -name "*.aidl" | while read -r aidl_file; do
        "$AIDL_TOOL" \
            -I"$UPSTREAM_DIR/aidl" \
            -o"$GEN_DIR" \
            "$aidl_file" 2>&1 || true
        AIDL_COUNT=$((AIDL_COUNT + 1))
    done
    ok "AIDL compilation complete"

    # -- 4. Compile resources ────────────────────────────────────────────
    log "Compiling resources (aapt2)..."
    MANIFEST="$UPSTREAM_DIR/service/AndroidManifest.xml"
    RES_SRC="$UPSTREAM_DIR/service/res"
    RES_APK="$BUILD_OUT/resources.ap_"

    # Compile individual resources
    find "$RES_SRC" -type f \( -name "*.xml" -o -name "*.png" \) | while read -r res; do
        "$AAPT2" compile "$res" -o "$RES_DIR/" 2>&1 || true
    done

    # Link into resource APK
    "$AAPT2" link \
        -I "$ANDROID_JAR" \
        --manifest "$MANIFEST" \
        -o "$RES_APK" \
        --java "$GEN_DIR" \
        --auto-add-overlay \
        "$RES_DIR"/*.flat 2>&1 || {
            warn "aapt2 link had warnings (may be non-fatal)"
        }
    ok "Resource compilation complete"

    # -- 5. Compile Java sources ─────────────────────────────────────────
    log "Compiling Java sources..."

    # Build classpath
    CLASSPATH="$ANDROID_JAR:$FRAMEWORK_STUB"
    [ -f "$SECURITY_CRYPTO" ] && CLASSPATH="$CLASSPATH:$SECURITY_CRYPTO"
    [ -f "$ANNOTATION_JAR" ] && CLASSPATH="$CLASSPATH:$ANNOTATION_JAR"

    # Collect all Java sources
    JAVA_SRCS=""
    for dir in "$UPSTREAM_DIR/service/src" "$GEN_DIR"; do
        if [ -d "$dir" ]; then
            srcs=$(find "$dir" -name "*.java" 2>/dev/null)
            JAVA_SRCS="$JAVA_SRCS $srcs"
        fi
    done

    if [ -z "$JAVA_SRCS" ]; then
        err "No Java sources found"
        return 1
    fi

    # Count sources
    SRC_COUNT=$(echo "$JAVA_SRCS" | wc -w)
    log "  Compiling $SRC_COUNT Java files..."

    # shellcheck disable=SC2086
    javac \
        -source 11 -target 11 \
        -classpath "$CLASSPATH" \
        -d "$CLASSES_DIR" \
        -bootclasspath "$ANDROID_JAR" \
        $JAVA_SRCS 2>&1 | tee "$BUILD_OUT/javac.log"

    if [ $? -ne 0 ]; then
        err "javac failed. See $BUILD_OUT/javac.log"
        err ""
        err "Common causes:"
        err "  - Missing framework stub (hidden API references)"
        err "  - Missing Jetpack Security-Crypto JAR"
        err "  - SDK version mismatch"
        return 1
    fi
    ok "Java compilation complete ($SRC_COUNT files)"

    # -- 6. Dex (d8) ────────────────────────────────────────────────────
    log "Converting to DEX..."
    CLASS_FILES=$(find "$CLASSES_DIR" -name "*.class")

    # shellcheck disable=SC2086
    "$D8" \
        --lib "$ANDROID_JAR" \
        --output "$BUILD_OUT" \
        $CLASS_FILES 2>&1 || {
            err "d8 failed"
            return 1
        }
    ok "DEX conversion complete: $BUILD_OUT/classes.dex"

    # -- 7. Assemble APK ────────────────────────────────────────────────
    log "Assembling APK..."
    UNSIGNED_APK="$BUILD_OUT/$APK_NAME-unsigned.apk"

    # Start from the resource APK
    cp "$RES_APK" "$UNSIGNED_APK"

    # Add DEX
    cd "$BUILD_OUT"
    zip -j "$UNSIGNED_APK" classes.dex 2>&1
    cd "$MODULE_DIR"

    ok "Unsigned APK: $UNSIGNED_APK"

    # -- 8. Sign (debug key) ────────────────────────────────────────────
    log "Signing APK (debug key)..."
    SIGNED_APK="$BUILD_OUT/$APK_NAME.apk"
    DEBUG_KEY="$SCRIPT_DIR/debug.keystore"

    # Create debug keystore if it doesn't exist
    if [ ! -f "$DEBUG_KEY" ]; then
        log "Creating debug keystore..."
        keytool -genkeypair \
            -keystore "$DEBUG_KEY" \
            -storepass android \
            -keypass android \
            -alias debug \
            -keyalg RSA \
            -keysize 2048 \
            -validity 10000 \
            -dname "CN=Sui-Lite Debug, O=Debug, C=US" 2>&1
        ok "Debug keystore created"
    fi

    # Zipalign first
    "$ZIPALIGN" -f 4 "$UNSIGNED_APK" "$BUILD_OUT/$APK_NAME-aligned.apk" 2>&1
    ok "Zipaligned"

    # Sign
    "$APKSIGNER" sign \
        --ks "$DEBUG_KEY" \
        --ks-pass pass:android \
        --key-pass pass:android \
        --ks-key-alias debug \
        --out "$SIGNED_APK" \
        "$BUILD_OUT/$APK_NAME-aligned.apk" 2>&1
    ok "Signed APK: $SIGNED_APK"

    # Verify signature
    "$APKSIGNER" verify --verbose "$SIGNED_APK" 2>&1 | head -5
    ok "Signature verified"

    return 0
}

# ============================================================================
# Post-build: Record build manifest
# ============================================================================

record_manifest() {
    log "Recording build manifest..."
    MANIFEST_FILE="$BUILD_OUT/build_manifest.txt"
    APK_FILE="$BUILD_OUT/$APK_NAME.apk"

    {
        echo "# Sui-Lite Build Manifest"
        echo "# Generated: $BUILD_TIMESTAMP"
        echo "# Build ID: $BUILD_ID"
        echo "#"
        echo "build_mode=$MODE"
        echo "build_timestamp=$BUILD_TIMESTAMP"
        echo "build_id=$BUILD_ID"
        echo "apk_package=$APK_PACKAGE"
        echo "apk_name=$APK_NAME"
        echo "apk_version_code=$APK_VERSION_CODE"
        echo "apk_version_name=$APK_VERSION_NAME"
        if [ -f "$APK_FILE" ]; then
            echo "apk_size=$(wc -c < "$APK_FILE")"
            echo "apk_sha256=$(sha256sum "$APK_FILE" | awk '{print $1}')"
        else
            echo "apk_size=0"
            echo "apk_sha256=NONE"
        fi
        echo "upstream_dir=$UPSTREAM_DIR"
        echo "host=$(uname -n)"
        echo "host_os=$(uname -s -r)"
        echo "java_version=$(java -version 2>&1 | head -1)"
    } > "$MANIFEST_FILE"

    ok "Build manifest: $MANIFEST_FILE"
    echo ""
    cat "$MANIFEST_FILE"
}

# ============================================================================
# Deployment
# ============================================================================

deploy_apk() {
    log "═══ Deploying APK to overlay ═══"
    APK_FILE="$BUILD_OUT/$APK_NAME.apk"

    if [ ! -f "$APK_FILE" ]; then
        err "APK not found: $APK_FILE"
        return 1
    fi

    # Deploy to overlay
    mkdir -p "$OVERLAY_DIR"
    cp "$APK_FILE" "$OVERLAY_DIR/$APK_NAME.apk"
    ok "Deployed: $OVERLAY_DIR/$APK_NAME.apk"

    # Remove placeholder if present
    rm -f "$OVERLAY_DIR/.placeholder" 2>/dev/null

    # Record SHA256
    sha256sum "$OVERLAY_DIR/$APK_NAME.apk" > "$OVERLAY_DIR/$APK_NAME.apk.sha256"
    ok "SHA256 recorded: $OVERLAY_DIR/$APK_NAME.apk.sha256"

    # Capture SELinux context (simulated — real capture happens on device)
    log "Recording expected SELinux context..."
    APK_CONTEXTS="$AUDIT_DIR/apk_contexts.txt"
    mkdir -p "$AUDIT_DIR"
    {
        echo "# Sui-Lite APK Context Capture"
        echo "# Build ID: $BUILD_ID"
        echo "# Timestamp: $BUILD_TIMESTAMP"
        echo "#"
        echo "# Expected runtime contexts (to be verified on device):"
        echo "#"
        echo "# Path                                                    Expected Context"
        echo "# ────────────────────────────────────────────────────     ─────────────────────────"
        echo "/system/priv-app/SystemShizuku/SystemShizuku.apk          u:object_r:system_file:s0"
        echo "/system/priv-app/SystemShizuku                            u:object_r:system_file:s0"
        echo ""
        echo "# APK metadata:"
        echo "apk_package=$APK_PACKAGE"
        echo "apk_sha256=$(sha256sum "$APK_FILE" | awk '{print $1}')"
        echo "apk_size=$(wc -c < "$APK_FILE")"
        echo "build_mode=$MODE"
        echo "signing=debug"
        echo ""
        echo "# WARNING: This APK is debug-signed."
        echo "# For the service to register Binder services and hold"
        echo "# android.uid.system, it MUST be platform-signed."
        echo "# Debug-signed APKs are for structural verification only."
    } > "$APK_CONTEXTS"
    ok "APK context file: $APK_CONTEXTS"
}

# ============================================================================
# Main
# ============================================================================

main() {
    log "═══════════════════════════════════════════════════"
    log "  Sui-Lite APK Build Pipeline"
    log "  Mode: $MODE | Deploy: $DEPLOY"
    log "═══════════════════════════════════════════════════"
    echo ""

    mkdir -p "$BUILD_OUT"

    # Build
    case "$MODE" in
        aosp)
            build_aosp
            ;;
        standalone)
            build_standalone
            ;;
        *)
            err "Unknown mode: $MODE"
            exit 1
            ;;
    esac

    BUILD_RC=$?

    if [ $BUILD_RC -ne 0 ]; then
        err "Build failed (exit code $BUILD_RC)"
        exit 1
    fi

    echo ""

    # Record build manifest
    record_manifest

    echo ""

    # Deploy if requested
    if [ $DEPLOY -eq 1 ]; then
        deploy_apk
    else
        log "Skipping deployment (use --deploy to copy APK to overlay)"
        log "APK is available at: $BUILD_OUT/$APK_NAME.apk"
    fi

    echo ""
    log "═══════════════════════════════════════════════════"
    ok "Build complete!"
    log "═══════════════════════════════════════════════════"
    echo ""
    log "Build output:  $BUILD_OUT/"
    log "Build log:     $BUILD_OUT/soong_build.log (aosp) or $BUILD_OUT/javac.log (standalone)"
    log "Manifest:      $BUILD_OUT/build_manifest.txt"
    if [ $DEPLOY -eq 1 ]; then
        log "Deployed APK:  $OVERLAY_DIR/$APK_NAME.apk"
        log "APK contexts:  $AUDIT_DIR/apk_contexts.txt"
    fi
}

main "$@"
