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
2. **Build** the APK from upstream sources (deterministic, auditable)
3. **Register** a custom Binder service via `app_process` for verification
4. **Observe** SELinux domain transitions, file contexts, and AVC denials
5. **Verify** that runtime state matches upstream policy expectations
6. **Release** automatically via GitHub Actions with full audit artifacts

This module does **NOT**:

- Inject custom SELinux allow rules
- Set SELinux to permissive
- Modify upstream code
- Suppress or hide AVC denials

---

## Attribution

| | |
|---|---|
| **Upstream repository** | [github.com/zerofrip/system_shizuku](https://github.com/zerofrip/system_shizuku) |
| **Original author** | zerofrip / The system_shizuku Project |
| **License** | Apache License 2.0 |
| **Upstream code location** | `upstream/system_shizuku/` (git submodule, unmodified) |

The upstream source is tracked as a **git submodule** at `upstream/system_shizuku/`.
No upstream file is renamed, merged, split, or modified.

---

## Repository Structure

```
Sui-Lite/
├── module.prop                  # Magisk module metadata
├── service.sh                   # Magisk service phase (Binder launch & observation)
├── post-fs-data.sh              # Magisk post-fs-data phase (overlay verification)
├── README.md                    # This file
├── .gitmodules                  # Submodule definition
│
├── upstream/                    # Upstream source (git submodule)
│   └── system_shizuku/          # https://github.com/zerofrip/system_shizuku
│       ├── Android.bp
│       ├── init.system_shizuku.rc
│       ├── aidl/
│       ├── sepolicy/
│       ├── service/
│       ├── permissions/
│       ├── settings-integration/
│       └── external/Shizuku-API/    # Nested submodule
│
├── overlay/                     # Magisk overlay mount paths
│   └── system/
│       ├── priv-app/SystemShizuku/  # APK deployment target
│       ├── etc/permissions/         # Permission XMLs (from upstream)
│       └── etc/init/                # init.rc (from upstream)
│
├── binder-service/              # Custom Binder service registration
│   ├── src/                     # Java sources (no dependencies)
│   ├── build.sh                 # DEX JAR compiler script
│   └── README.md                # Binder-specific documentation
│
├── build/                       # APK build pipeline
│   ├── build_apks.sh            # Deterministic APK build script
│   ├── env_check.sh             # Build environment validator
│   ├── README.build.md          # Build documentation
│   └── libs/                    # Jetpack dependencies (downloaded)
│
├── audit/                       # SELinux observation & verification
│   ├── scripts/                 # Capture & verification scripts
│   │   ├── capture_contexts.sh
│   │   ├── capture_denials.sh
│   │   ├── verify_domains.sh
│   │   └── capture_binder_contexts.sh
│   ├── selinux/                 # Example audit output
│   │   ├── contexts.before.txt
│   │   ├── contexts.after.txt
│   │   ├── denials.log
│   │   ├── domain.map
│   │   └── binder_contexts.txt
│   └── upstream/                # Upstream diff reports (CI-generated)
│
└── .github/workflows/           # CI/CD automation
    ├── upstream-sync.yml        # Upstream submodule tracking
    └── build-and-release.yml    # APK build + module ZIP + GitHub Release
```

---

## CI/CD Pipeline

### Upstream Sync (`upstream-sync.yml`)

| | |
|---|---|
| **Trigger** | Manual dispatch or weekly (Monday 06:00 UTC) |
| **Action** | Updates `upstream/system_shizuku/` submodule, syncs overlay files, generates diff |
| **Output** | Commit with updated submodule ref + `audit/upstream/upstream_diff.txt` |

### Build and Release (`build-and-release.yml`)

| | |
|---|---|
| **Trigger** | Push to `main` (upstream/overlay/build changes) or manual dispatch |
| **Action** | Detect changes → Build APK → Assemble Magisk ZIP → Create GitHub Release |
| **Tag format** | `sui-lite-<upstream_commit_hash>` |
| **Release body** | Verbatim upstream commit message + module metadata |

Each release includes:

| Artifact | Description |
|----------|-------------|
| `Sui-Lite-*.zip` | Flashable Magisk module |
| `apk_hashes.txt` | SHA256 hashes of all APKs |
| `rebuilt_apks.json` | Build metadata (JSON) |
| `deployment_tree.txt` | Full module file tree |
| `upstream_diff.txt` | Changes from upstream (if synced) |
| `build_manifest.txt` | Build environment details |

---

## Building APKs

Two build modes are supported:

| Mode | Command | Signing | Binder Registration |
|------|---------|---------|---------------------|
| **AOSP tree** | `./build/build_apks.sh --aosp --deploy` | Platform key | ✅ Works |
| **Standalone** | `./build/build_apks.sh --standalone --deploy` | Debug key | ❌ Structural only |

```bash
# Check build environment
./build/env_check.sh

# Build and deploy to overlay
./build/build_apks.sh --standalone --deploy
```

> [!WARNING]
> Debug-signed APKs **cannot** register Binder services because they lack
> `android.uid.system`. The standalone build is for structural verification only.
> For full functional testing, use the AOSP tree build with platform signing.

For standalone builds, you need a framework stub for hidden API access:
```bash
adb pull /system/framework/framework.jar build/framework-stub.jar
```

See [`build/README.build.md`](build/README.build.md) for full documentation.

---

## Installation

### From GitHub Releases (recommended)

1. Download the latest `Sui-Lite-*.zip` from [Releases](https://github.com/zerofrip/Sui-Lite/releases)
2. Flash via Magisk Manager → Modules → Install from storage
3. Reboot

### From source

```bash
git clone --recurse-submodules https://github.com/zerofrip/Sui-Lite.git
cd Sui-Lite

# Option A: Use a pre-built platform-signed APK
cp /path/to/SystemShizuku.apk overlay/system/priv-app/SystemShizuku/

# Option B: Build from source (debug-signed)
./build/build_apks.sh --standalone --deploy

# Create flashable ZIP
zip -r ../Sui-Lite.zip . -x '.git/*' 'upstream/system_shizuku/.git/*' 'build/out/*'
```

### Required environment

| Component | Minimum Version |
|-----------|----------------|
| **Rooted Android device** | Android 11+ |
| **Magisk** | v26+ |
| **SELinux** | Enforcing (recommended) |

> [!IMPORTANT]
> The module is designed to operate under **SELinux Enforcing mode**.
> AVC denials are expected and intentionally captured for analysis.

---

## Collecting Audit Data

All audit output is written to `/data/local/tmp/sui-lite/` on the device.

### Automated (runs on boot)

```
/data/local/tmp/sui-lite/
├── post-fs-data.log        # post-fs-data phase log
├── service.log             # service phase log
├── contexts.before.txt     # SELinux contexts before activation
├── contexts.after.txt      # SELinux contexts after activation
├── denials.log             # AVC denial capture
└── domain.map              # Domain verification results (PASS/FAIL/SKIP)
```

### Manual

```bash
# Capture SELinux file contexts
adb shell sh /data/adb/modules/sui-lite/audit/scripts/capture_contexts.sh "manual" /data/local/tmp/sui-lite

# Capture AVC denials
adb shell sh /data/adb/modules/sui-lite/audit/scripts/capture_denials.sh /data/local/tmp/sui-lite

# Verify domains
adb shell sh /data/adb/modules/sui-lite/audit/scripts/verify_domains.sh /data/local/tmp/sui-lite

# Pull results
adb pull /data/local/tmp/sui-lite/ ./audit-results/
```

---

## Interpreting Audit Output

### `contexts.before.txt` / `contexts.after.txt`

SELinux file contexts for all system_shizuku-relevant paths.
Diff to see what changed after module activation:

```bash
diff contexts.before.txt contexts.after.txt
```

### `denials.log`

AVC denials filtered for `system_shizuku` / `shizuku`. These document
exactly what policy rules are **required**. Use them to generate targeted
`sepolicy.rule` entries — do NOT suppress them.

### `domain.map`

PASS/FAIL/SKIP results for each verification check:
- **PASS** — runtime state matches upstream expectation
- **FAIL** — mismatch detected (investigate)
- **SKIP** — component not available (service not started, APK missing)

---

## SELinux Approach

1. **Enforcing mode** is the default. The module observes real constraints.
2. **No policy injection.** No `sepolicy.rule` file is included.
3. **AVC denials are informational.** They tell you what rules upstream requires.
4. **Domain transitions require device-level policy.** The upstream `init.rc`
   specifies `seclabel u:r:system_shizuku:s0` — the device's SELinux policy
   must define this type.

---

## Upstream Reference

Key files in `upstream/system_shizuku/` for SELinux analysis:

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
`build/`, `audit/scripts/`, `.github/workflows/`) is released under the same license.
