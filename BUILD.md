# Build and validation

Verified local toolchain: Xcode 27.1 (27A9275), Apple clang 21.0.0, iPhoneOS 27.1 SDK, ldid 2.1.5 and RootHide Theos at `cfba89a53a05b4a1b822121158acc3669c20602f` from `https://github.com/roothide/theos.git`.

Two package schemes are supported, both version 1.0 with deployment target iOS 26.0:

- `rootless`: package architecture `iphoneos-arm64`, containing arm64 and modern arm64e slices. Files install under `/var/jb` and dependencies use the rootless search paths.
- `roothide`: package architecture `iphoneos-arm64e`, containing the native modern arm64e slice. Files install under RootHide's jailbreak layout and link libroothide.

`ABTPaths.h` uses standard libroot path conversion on rootless and native `jbroot` on RootHide. The existing preference domain remains the same. No AutoPatches marker, rootless compatibility dependency or legacy engine is included. The script builds each variant separately with a clean between schemes; it does not relabel an existing binary.

On this Mac, from the source directory:

```sh
export THEOS=/absolute/path/to/roothide/theos
sh build.sh all
```

On another Mac, install Xcode and its command-line tools, Python 3, ldid and the native RootHide Theos checkout with its submodules; point `THEOS` at that checkout. Select Xcode as the developer directory. No downloaded system private headers are required. `Settings/vendor/Preferences.framework` contains only a minimal link stub; it is not packaged. The `PSViewController` header comes from Theos’s standard headers submodule.

Use `sh build.sh rootless` or `sh build.sh roothide` to build only one variant.

`build.sh` runs both host suites with AddressSanitizer and UndefinedBehaviorSanitizer, compiles the engine and preference bundle, signs them, normalizes archive ownership to root:wheel and validates the resulting `.deb`.

Output:

```text
packages/com.sahinkaa.askbeforecallingtoo26_1.0_iphoneos-arm64.deb
packages/com.sahinkaa.askbeforecallingtoo26_1.0_iphoneos-arm64e.deb
validation/tests.log
validation/package-rootless.json
validation/package-roothide.json
```

The package validator checks archive paths and exact payload inventory, ownership/modes, all expected architecture slices, iOS deployment target, scheme-specific library references and rootless install prefix, preference registration, settings inventory and every code-page hash in the ad-hoc CodeDirectories. These are offline structural checks, not device trust or behavior certification.

The runtime tests compile the actual `Engine/Runtime.m` against macOS UIKit/Contacts doubles and install its nine hook functions into fixture classes. They exercise cancellation, approval, repeated taps/callbacks, callback queue affinity, emergency bypass, changed recipients/drafts, Cc/Bcc, unavailable/background presenters, dismissal, category/master disable, whitelist modes and custom text/order. Call fixtures cover DialerController → UIApplication, ContactsUICore → launchAppForDialRequest future/error adapter, direct LaunchServices sync/async wrappers, NSExtensionContext URL handoff and the contact-number local adapter with its separate BOOL/error callback and legacy backend. They check process routing for Contacts/card services, a visible foreground hosted card with inactive service-app state, rejection after the scene backgrounds, preserved options/SIM/endpoint/configuration, independent sync callbacks and scoped nested approvals. Workspace, Contacts adapter and extension fixtures use unique names so they cannot bind to macOS system classes; the device validator checks those names are absent from the device binary.

The settings tests exercise the shipped schema, defaults, type validation, atomic merge/save/readback, backups, malformed-file preservation, Unicode text and contact/address add/remove operations. The RootHide behavior was verified by the user on the setup documented in README.md. The rootless variant still needs device testing.

Debug symbols are generated under `.theos/obj/arm64e`. Keep the matching dSYMs and validation manifest when diagnosing a crash.

The rootless scheme and package architecture follow [Theos rootless documentation](https://theos.dev/docs/rootless). Both control files must retain `Author: tateu • sahinkaa` and `Version: 1.0`; the validator checks these fields.
