# Build and validation

Verified local toolchain: Xcode 27.1 (27A9275), Apple clang 21.0.0, iPhoneOS 27.1 SDK, ldid 2.1.5 and RootHide Theos at `cfba89a53a05b4a1b822121158acc3669c20602f` from `https://github.com/roothide/theos.git`.

The package is native RootHide, architecture `iphoneos-arm64e`, CPU subtype `0x80000002`, deployment target iOS 26.0. It links RootHide and the substrate-compatible hook library. It contains no AutoPatches marker, rootless compatibility dependency or prebuilt legacy engine. Standard rootless requires a separate build configuration; do not relabel this package.

On this Mac, from the source directory:

```sh
export THEOS=/absolute/path/to/roothide/theos
sh build.sh
```

On another Mac, install Xcode and its command-line tools, Python 3, ldid and the native RootHide Theos checkout with its submodules; point `THEOS` at that checkout. Select Xcode as the developer directory. No downloaded system private headers are required. `Settings/vendor/Preferences.framework` contains only a minimal link stub and header for `PSViewController`; it is not packaged.

`build.sh` runs both host suites with AddressSanitizer and UndefinedBehaviorSanitizer, compiles the engine and preference bundle, signs them, normalizes archive ownership to root:wheel and validates the resulting `.deb`.

Output:

```text
packages/com.sahinkaa.askbeforecallingtoo26_1.0_iphoneos-arm64e.deb
validation/tests.log
validation/package.json
```

The package validator checks archive paths and exact payload inventory, ownership/modes, native arm64e subtype, iOS deployment target, RootHide library references, preference registration, settings inventory and every code-page hash in the ad-hoc CodeDirectories. These are offline structural checks, not device trust or behavior certification.

The runtime tests compile the actual `Engine/Runtime.m` against macOS UIKit/Contacts doubles and install its nine hook functions into fixture classes. They exercise cancellation, approval, repeated taps/callbacks, callback queue affinity, emergency bypass, changed recipients/drafts, Cc/Bcc, unavailable/background presenters, dismissal, category/master disable, whitelist modes and custom text/order. Call fixtures cover DialerController → UIApplication, ContactsUICore → launchAppForDialRequest future/error adapter, direct LaunchServices sync/async wrappers, NSExtensionContext URL handoff, and the contact-number local adapter with its separate BOOL/error callback and legacy backend. They check process routing for Contacts/card services, a visible foreground hosted card with inactive service-app state, rejection after the scene backgrounds, preserved options/SIM/endpoint/configuration, independent sync callbacks, and scoped nested approvals. Workspace, Contacts adapter and extension fixtures use unique names so they cannot bind to macOS system classes; the device validator checks those names are absent from the device binary.

The settings tests exercise the shipped schema, defaults, type validation, atomic merge/save/readback, backups, malformed-file preservation, Unicode text and contact/address add/remove operations. On-device UI layout, current private method signatures and routing remain to be checked by the user.

Debug symbols are generated under `.theos/obj/arm64e`. Keep the matching dSYMs and validation manifest when diagnosing a crash.
