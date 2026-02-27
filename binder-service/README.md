# Binder Service — Sui-Lite

## Overview

This directory contains a minimal custom Binder service that
registers with Android's `ServiceManager` via `app_process`.

It exists solely for **verification and auditing** — proving that
a Magisk module can register a Binder service and capturing the
SELinux behavior that results.

---

## Architecture

```
binder-service/
├── src/com/suilite/binder/
│   ├── BinderEntryPoint.java    # app_process entry point
│   └── SuiLiteService.java      # Binder implementation
├── build.sh                      # Compile to DEX JAR
├── binder-service.jar            # Built output (DEX)
├── build_manifest.txt            # Build metadata
└── README.md                     # This file
```

---

## How It Works

### Launch sequence (in `service.sh`)

1. Wait for `ServiceManager` to be responsive
2. Optionally wait for Shizuku upstream services
3. Kill any existing instance
4. Launch via `app_process`:
   ```
   /system/bin/app_process \
     -Djava.class.path=binder-service.jar \
     /system/bin \
     com.suilite.binder.BinderEntryPoint
   ```
5. `BinderEntryPoint.main()` registers `SuiLiteService` as `sui_lite_binder`
6. Enters `Looper.loop()` to stay alive

### Service interface (raw Parcel, no AIDL)

| Transaction | Code | Response |
|-------------|------|----------|
| PING | 1 | `"sui-lite-alive"` |
| GET_INFO | 2 | UID, PID, SELinux context, service name |

---

## Building

```bash
# Requires: ANDROID_HOME, framework-stub.jar
./binder-service/build.sh
```

Output: `binder-service/binder-service.jar`

---

## Testing on device

```bash
# Push and launch manually
adb push binder-service/binder-service.jar /data/local/tmp/
adb shell /system/bin/app_process \
  -Djava.class.path=/data/local/tmp/binder-service.jar \
  /system/bin com.suilite.binder.BinderEntryPoint &

# Check registration
adb shell service list | grep sui_lite

# Check logs
adb shell logcat -s SuiLiteBinder
```

---

## SELinux Behavior

Under **Enforcing mode** without custom policy, the expected behavior is:

1. `app_process` launches in the `magisk` domain (or `su` depending on root method)
2. `ServiceManager.addService()` triggers an **AVC denial**:
   ```
   avc: denied { add } for service=sui_lite_binder
     scontext=u:r:magisk:s0
     tcontext=u:object_r:default_android_service:s0
     tclass=service_manager
   ```
3. The service **stays alive** despite the registration failure
4. Audit scripts capture the denial and process domain

This is **intentional** — the service's purpose is to make the
SELinux interaction observable.

---

## Upstream Compatibility

This service is **completely isolated** from upstream `system_shizuku`:

- Different service name (`sui_lite_binder` vs `shizuku` / `system_shizuku`)
- Different package (`com.suilite.binder` vs `com.android.systemshizuku`)
- No shared code, no AIDL dependencies
- Lives in `binder-service/`, not `upstream/`

Upstream updates propagate through the submodule without affecting
this service. The service observes upstream state but does not
depend on it.
