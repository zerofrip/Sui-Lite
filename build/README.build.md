# Sui-Lite Build Guide

## Overview

This directory contains scripts to build SystemShizuku from upstream sources
and deploy the resulting APK into the Magisk overlay.

Two build modes are supported:

| Mode | Command | Prerequisites |
|------|---------|---------------|
| **AOSP tree** | `./build/build_apks.sh --aosp` | Full AOSP source with `lunch` target |
| **Standalone** | `./build/build_apks.sh --standalone` | Android SDK + framework stub |

---

## Quick Start

```bash
# Check your environment
./build/env_check.sh

# Build and deploy
./build/build_apks.sh --standalone --deploy
```

---

## Host Environment Requirements

### Common (both modes)

| Tool | Minimum Version | Purpose |
|------|----------------|---------|
| Java JDK | 11+ | Compile Java sources |
| `sha256sum` | any | APK hash verification |
| `zip` / `unzip` | any | APK assembly |

### AOSP Tree Mode (`--aosp`)

| Requirement | Notes |
|-------------|-------|
| `ANDROID_BUILD_TOP` | Set via `source build/envsetup.sh && lunch <target>` |
| Soong build system | Included in AOSP source |
| Platform signing keys | Built APK uses `certificate: "platform"` from `Android.bp` |

The AOSP build produces a **platform-signed** APK — the only variant
that can actually register Binder services with `ServiceManager`.

### Standalone Mode (`--standalone`)

| Requirement | Notes |
|-------------|-------|
| `ANDROID_HOME` | Android SDK path |
| `aapt2` | In SDK build-tools |
| `d8` | In SDK build-tools |
| `aidl` | In SDK build-tools |
| `apksigner` | In SDK build-tools |
| `zipalign` | In SDK build-tools |
| `framework-stub.jar` | See below |

#### Framework Stub

The upstream code uses hidden Android platform APIs not in the public SDK:

| API | Usage in upstream |
|-----|-------------------|
| `android.os.ServiceManager` | Binder service registration |
| `android.app.ActivityThread` | System context creation |
| `android.util.Slog` | System logging |
| `android.os.SystemProperties` | Property access |
| `Intent.getIBinderExtra()` | Binder passing via Intent |

To obtain the framework stub:

```bash
# From device (requires root):
adb pull /system/framework/framework.jar build/framework-stub.jar

# From AOSP build output:
cp $ANDROID_BUILD_TOP/out/target/common/obj/JAVA_LIBRARIES/framework_intermediates/classes.jar \
   build/framework-stub.jar
```

#### Jetpack Dependencies

PermissionStore requires Jetpack Security-Crypto:

```bash
mkdir -p build/libs
wget -O build/libs/security-crypto.jar \
  "https://repo1.maven.org/maven2/androidx/security/security-crypto/1.1.0-alpha06/security-crypto-1.1.0-alpha06.jar"
wget -O build/libs/annotation.jar \
  "https://repo1.maven.org/maven2/androidx/annotation/annotation/1.7.0/annotation-1.7.0.jar"
```

---

## Build Output

All artifacts are written to `build/out/`:

```
build/out/
├── SystemShizuku.apk           # Final signed APK
├── SystemShizuku-unsigned.apk  # Pre-signing artifact
├── SystemShizuku-aligned.apk   # Post-zipalign artifact
├── classes.dex                 # Compiled DEX
├── classes/                    # Compiled .class files
├── gen/                        # AIDL-generated Java
├── res/                        # Compiled resources
├── resources.ap_               # Resource APK
├── build_manifest.txt          # Build metadata
├── javac.log                   # Compiler output
└── soong_build.log             # AOSP build output (--aosp mode)
```

### Build Manifest

`build_manifest.txt` records:

```
build_mode=standalone
build_timestamp=2026-02-27T21:45:00Z
build_id=20260227_214500
apk_package=com.android.systemshizuku
apk_name=SystemShizuku
apk_version_code=1
apk_version_name=1.0
apk_size=48231
apk_sha256=a1b2c3d4e5f6...
```

---

## Deployment

With `--deploy`, the APK is copied to the Magisk overlay:

```
overlay/system/priv-app/SystemShizuku/
├── SystemShizuku.apk
└── SystemShizuku.apk.sha256
```

SELinux expected contexts are recorded to:

```
audit/selinux/apk_contexts.txt
```

---

## Verification Steps

### 1. Verify build integrity

```bash
# Check the APK hash
sha256sum build/out/SystemShizuku.apk
cat build/out/build_manifest.txt | grep sha256

# Verify signature
apksigner verify --verbose build/out/SystemShizuku.apk
```

### 2. Verify deployment

```bash
# Check overlay contents
ls -la overlay/system/priv-app/SystemShizuku/
cat overlay/system/priv-app/SystemShizuku/SystemShizuku.apk.sha256
```

### 3. On-device verification

```bash
# After flashing the module and rebooting:
adb shell ls -laZ /system/priv-app/SystemShizuku/
adb shell pm list packages | grep systemshizuku
adb shell service list | grep shizuku
```

---

## Signing Modes

| Mode | Signing | Binder Registration | Use Case |
|------|---------|---------------------|----------|
| AOSP (`--aosp`) | Platform key | ✅ Works | Full functional test |
| Standalone (`--standalone`) | Debug key | ❌ Fails | Structural verification only |

> **WARNING**: Debug-signed APKs cannot register with `ServiceManager` because
> they lack `android.uid.system` shared UID. The standalone build is for
> verifying compilation, structure, and overlay mechanics only. For full
> functional testing, use the AOSP tree build with platform signing.

---

## Common Failure Modes

| Error | Cause | Fix |
|-------|-------|-----|
| `framework-stub.jar not found` | Missing hidden API stubs | `adb pull /system/framework/framework.jar build/framework-stub.jar` |
| `aapt2 not found` | SDK build-tools not installed | `sdkmanager "build-tools;34.0.0"` |
| `javac: cannot find symbol ServiceManager` | Missing framework stub | See Framework Stub section |
| `d8: unsupported class file version` | Java version mismatch | Use JDK 11 or 17 |
| `Soong build failed` | AOSP environment not set up | `source build/envsetup.sh && lunch <target>` |
| `security-crypto.jar not found` | Missing Jetpack dependency | See Jetpack Dependencies section |

---

## Tracking Upstream Changes

When `upstream/system_shizuku/` is updated:

1. Re-run `./build/build_apks.sh --standalone --deploy`
2. Compare `build_manifest.txt` (SHA256 will differ)
3. Diff `audit/selinux/apk_contexts.txt` for context changes
4. On device: re-flash module, reboot, pull audit data
5. Diff `contexts.before.txt` / `contexts.after.txt` / `domain.map`
