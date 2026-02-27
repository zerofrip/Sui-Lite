# Sui-Lite

> **Verification-oriented Magisk module** that faithfully reproduces
> [`system_shizuku`](https://github.com/zerofrip/system_shizuku) behavior
> and makes SELinux interactions explicitly observable.

> [!CAUTION]
> This module is for **debugging, auditing, and behavioral verification only**.
> It is **NOT** intended for production use. It does not harden, optimize,
> or stealth-persist any functionality.

---

## Purpose

Sui-Lite exists to:

1. **Reproduce** `system_shizuku` behavior via Magisk overlay
2. **Observe** SELinux domain transitions, file contexts, and AVC denials
3. **Verify** that runtime state matches upstream policy expectations
4. **Document** discrepancies without silently fixing them

This module does **NOT**:

- Inject custom SELinux allow rules
- Set SELinux to permissive
- Modify upstream code
- Suppress or hide AVC denials

All SELinux policy decisions are left to the operator.

---

## Attribution

| | |
|---|---|
| **Upstream repository** | [github.com/zerofrip/system_shizuku](https://github.com/zerofrip/system_shizuku) |
| **Original author** | zerofrip / The system_shizuku Project |
| **License** | Apache License 2.0 |
| **Upstream code location** | `upstream/system_shizuku/` (verbatim, unmodified) |

All upstream files in `upstream/system_shizuku/` are **byte-for-byte copies**
of the original repository. No file has been renamed, merged, split, or modified.

---

## Required Environment

| Component | Minimum Version |
|-----------|----------------|
| **Rooted Android device** | Android 11+ |
| **Magisk** | v26+ |
| **Shizuku** | Installed on device |
| **Sui** | Installed on device |
| **SELinux** | Enforcing (recommended) |

> [!IMPORTANT]
> The module is designed to operate under **SELinux Enforcing mode**.
> AVC denials are expected and intentionally captured for analysis.
> Do NOT set SELinux to permissive to "fix" functionality — that defeats
> the purpose of this module.

---

## Directory Structure

```
Sui-Lite/
├── module.prop              # Magisk module metadata
├── service.sh               # Magisk service phase (observation only)
├── post-fs-data.sh          # Magisk post-fs-data phase (overlay verification)
├── README.md                # This file
│
├── upstream/                # Verbatim upstream mirror (immutable)
│   └── system_shizuku/     # Complete copy of the source repository
│       ├── Android.bp
│       ├── init.system_shizuku.rc
│       ├── aidl/
│       ├── sepolicy/
│       ├── service/
│       ├── permissions/
│       ├── settings-integration/
│       └── ...
│
├── overlay/                 # Magisk overlay mount paths
│   └── system/
│       ├── priv-app/SystemShizuku/    # APK goes here
│       ├── etc/permissions/           # Permission XMLs (verbatim)
│       └── etc/init/                  # init.rc (verbatim)
│
└── audit/                   # SELinux observation & verification
    ├── selinux/             # Captured audit output (runtime)
    │   ├── contexts.before.txt
    │   ├── contexts.after.txt
    │   ├── denials.log
    │   └── domain.map
    └── scripts/             # Capture & verification scripts
        ├── capture_contexts.sh
        ├── capture_denials.sh
        └── verify_domains.sh
```

---

## Installation

### 1. Prepare the module

```bash
# Clone or download this repository
git clone https://github.com/zerofrip/Sui-Lite.git
```

### 2. Provide the SystemShizuku APK

The module **cannot compile Java source**. You must build the APK from the
upstream AOSP source and place it in the overlay:

```bash
cp SystemShizuku.apk Sui-Lite/overlay/system/priv-app/SystemShizuku/
```

> [!WARNING]
> The APK must be **platform-signed** (signed with the ROM's platform key).
> An unsigned or debug-signed APK will fail to register Binder services
> because it uses `android:sharedUserId="android.uid.system"`.

### 3. Flash via Magisk

```bash
# Create a flashable zip
cd Sui-Lite
zip -r ../Sui-Lite.zip . -x '.git/*'

# Flash via Magisk Manager or TWRP
# Magisk Manager → Modules → Install from storage → Sui-Lite.zip
```

### 4. Reboot

After reboot, the module will:
- Overlay permission XMLs and init.rc into `/system/`
- Verify overlay visibility
- Capture SELinux contexts (before and after)
- Check service registration status
- Capture AVC denials

---

## Collecting Audit Data

All audit output is written to `/data/local/tmp/sui-lite/` on the device.

### Automated collection (runs on boot)

The `service.sh` script automatically invokes audit scripts on every boot.
Data is available at:

```
/data/local/tmp/sui-lite/
├── post-fs-data.log        # post-fs-data phase log
├── service.log             # service phase log
├── contexts.before.txt     # SELinux contexts before activation
├── contexts.after.txt      # SELinux contexts after activation
├── denials.log             # AVC denial capture
└── domain.map              # Domain verification results
```

### Manual collection

You can also run the scripts manually via ADB:

```bash
# Capture SELinux file contexts
adb shell sh /data/adb/modules/sui-lite/audit/scripts/capture_contexts.sh "manual" /data/local/tmp/sui-lite

# Capture AVC denials
adb shell sh /data/adb/modules/sui-lite/audit/scripts/capture_denials.sh /data/local/tmp/sui-lite

# Verify domains
adb shell sh /data/adb/modules/sui-lite/audit/scripts/verify_domains.sh /data/local/tmp/sui-lite
```

### Live denial monitoring

```bash
# Watch denials in real time
adb shell dmesg -w | grep -i 'avc.*denied'

# Or via logcat
adb shell logcat -b all | grep -i 'avc.*denied'
```

### Pull results to host

```bash
adb pull /data/local/tmp/sui-lite/ ./audit-results/
```

---

## Interpreting Audit Output

### `contexts.before.txt` / `contexts.after.txt`

Contains SELinux file contexts for all system_shizuku-relevant paths.
Diff these to see what changed after module activation:

```bash
diff contexts.before.txt contexts.after.txt
```

**Expected:** Overlay files should appear with `u:object_r:system_file:s0`
context after activation. Missing entries indicate overlay failure.

### `denials.log`

Contains AVC denial messages filtered for `system_shizuku` / `shizuku`.

**Expected under Enforcing mode:** Denials for the `system_shizuku` domain
if no custom SELinux policy has been loaded. Common denials:

```
avc: denied { add } for service=shizuku scontext=u:r:system_shizuku:s0 ...
avc: denied { find } for service=shizuku scontext=u:r:untrusted_app:s0 ...
```

**Action:** These denials document what policy rules are **required**.
Use them to generate targeted `sepolicy.rule` entries or device-level
policy patches. Do NOT suppress them.

### `domain.map`

Shows PASS/FAIL/SKIP results for each verification check:

- **PASS** — runtime state matches upstream expectation
- **FAIL** — mismatch detected (investigate)
- **SKIP** — component not available (service not started, APK missing, etc.)

---

## SELinux Assumptions

This module operates under these assumptions:

1. **Enforcing mode is the default.** The module is designed to observe
   behavior under real SELinux constraints.

2. **No policy injection.** The module does NOT include a `sepolicy.rule`
   file. All SELinux types (`system_shizuku`, `system_shizuku_service`,
   `system_shizuku_data_file`, etc.) exist **only in the upstream policy
   definitions** at `upstream/system_shizuku/sepolicy/`.

3. **AVC denials are informational.** They tell you exactly what policy
   rules the upstream service requires. The decision to add those rules
   is yours.

4. **Domain transitions require device-level policy.** The upstream
   `init.system_shizuku.rc` specifies `seclabel u:r:system_shizuku:s0`,
   which requires the device's SELinux policy to define the
   `system_shizuku` type. Without it, the service will run in `init`
   domain or fail to start.

---

## Upstream Reference

The `upstream/system_shizuku/` directory contains a complete, unmodified
copy of the source repository. Key files for SELinux analysis:

| File | Purpose |
|------|---------|
| `sepolicy/system_shizuku.te` | Type declarations, allow rules, neverallow rules |
| `sepolicy/file_contexts` | File path → label mapping |
| `sepolicy/service_contexts` | Binder service → label mapping |
| `init.system_shizuku.rc` | Service definition with `seclabel` |
| `service/AndroidManifest.xml` | Permissions and component declarations |

---

## License

This module packages upstream code under the **Apache License 2.0**.
See the upstream repository for full license text.

All files in `upstream/system_shizuku/` are copyright their original authors.
The Magisk integration layer (`module.prop`, `service.sh`, `post-fs-data.sh`,
`audit/scripts/`) is released under the same license.
