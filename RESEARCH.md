# Implementation notes

The confirmation engine and Settings pane were rebuilt for iOS 26. The legacy AskBeforeCalling Too binary is not bundled. Native device-support symbols from iOS 26.0.1 were used to inspect the outgoing action paths. Runtime hooks use class and selector lookup, with argument and return-type validation before installation; framework addresses are not hard-coded.

## Calls

Supported call routes include UIApplication URL opening, TUCallCenter dialing/launching, configuration-based LSApplicationWorkspace opening and NSExtensionContext URL opening. Contact-number rows use a distinct CNLaunchServicesLocalAdapter background handoff. Its legacy LaunchServices options/error backend does not enter the configuration-based workspace method, so the adapter is gated separately.

The adapter's void asynchronous method preserves its native promise and BOOL/NSError reply. It captures the URL and options before showing confirmation. Cancel returns false and NSUserCancelledError. Approval forwards the original action once off the UI thread. No synchronous NSError** storage is retained after a method returns. Synchronous workspace wrappers complete their original callback before returning and use an independent callback for approved deferred transport.

Native TUDialRequest parsing and TUCallCenter emergency classification preserve emergency bypass. The system framework can be loaded on demand in contact-card processes before classification. URLs retain their original destination, SIM/provider options, endpoint and query. A thread-scoped exact-URL approval prevents duplicate prompts in nested synchronous handoffs without granting a timed exemption for later calls.

## Messages and Mail

Messages confirmation occurs at CKChatController.sendComposition:animations:, before the original clears the draft. Recipient, text, subject, attachment identity and payload snapshots are revalidated before approval. Mail confirmation occurs at MFMailComposeController.performSend: and includes To, Cc and Bcc recipients. Cancel does not invoke the original send method.

## Settings and control flow

The pane uses a native UIKit controller rather than relying on legacy preference-controller ivar layouts. Preference writes merge atomically, retain unknown keys and preserve malformed input rather than overwriting it. Whitelists use normalized full addresses instead of partial phone-number matching.

Each transaction resolves once. Repeated attempts, unavailable presenters, backgrounding, dismissal and timeout do not grant consent. UI work runs on the main thread; call replay follows the verified callback contract. Optional getters are signature checked. There are no raw assembly patches, stack-pointer modifications, undefined-key KVC shims or exception-based retries of original actions. Dyld callbacks defer Objective-C work outside the loader lock.

The injection filter covers the supported app and contact-service processes. No SpringBoard or telephony-daemon injection is included. Reports contain hook status and decisions, excluding recipients and message bodies.

## Verification

Host tests compile the actual runtime hooks against isolated UIKit/Contacts doubles with AddressSanitizer and UndefinedBehaviorSanitizer. They exercise confirmation, cancellation, repeats, callbacks, foreground state, preserved targets/options, emergency behavior, settings persistence and whitelist matching. Offline package checks validate archive paths, ownership, architecture, deployment target, RootHide dependencies and signed code-page hashes. These checks complement device testing; they do not establish compatibility outside the tested setup documented in README.md.

## Package variants

The same confirmation engine and preference store compile for rootless and RootHide. `ABTPaths.h` selects libroot path conversion for standard rootless or native `jbroot` for RootHide. Only build configuration, path resolution and package metadata differ between variants. Rootless ships both arm64 and modern arm64e slices under `/var/jb`; RootHide ships native modern arm64e. Both packages use the author display `tateu • sahinkaa` with the U+2022 bullet. The maintainer remains sahinkaa. Settings are reread for each action, so changing them does not require a respring.
