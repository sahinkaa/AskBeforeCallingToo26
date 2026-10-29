# AskBeforeCalling Too 26

Confirm before making calls or sending messages and emails on iOS 26.

Rebuilt for iOS 26 by [sahinkaa](https://github.com/sahinkaa), inspired by **AskBeforeCalling Too** by **tateu (Josh Harris)**. The original preference icon is retained. This is an independent rebuild with a new confirmation engine and Settings pane; the original tweak engine is not bundled.

## Features

- Confirmation for outgoing calls from Phone's keypad, Favorites, Recents and contact-number rows, including the separate Contacts app.
- One **Calls** switch for supported phone and FaceTime dial actions.
- Confirmation before sending messages in Apple Messages and emails in Apple Mail.
- Contact whitelists, an option to allow all contacts for calls, and all/any-recipient matching for messages and emails.
- Custom confirmation text and button labels, with optional reversed button order.
- A native Settings pane with persistent preferences on iOS 26.

The old separate Phone/FaceTime categories, Caller ID blocking, CallBar integration and message-notification options have been removed.

## Tested setup

**Tested only on iPhone 11 Pro Max, iOS 26.0.1, Dopamine 3 RootHide.** Calls from the keypad, Favorites, Recents and contact pages in both Phone and Contacts, message/email confirmation, Settings options and contact whitelisting were verified on that device. Other devices, iOS versions and jailbreaks have not been verified.

## Installation

1. Download `com.sahinkaa.askbeforecallingtoo26_1.0_iphoneos-arm64e.deb` from [Releases](https://github.com/sahinkaa/AskBeforeCallingToo26/releases/latest).
2. Open it in Sileo and install it directly on RootHide. **Do not convert this native RootHide package with Patcher.**
3. Respring, then open **Settings → AskBeforeCalling Too 26**.
4. Enable the protections you want. Changes apply to the next action without another respring.

The package replaces the old AskBeforeCalling Too packages. Settings use the existing `net.tateu.askbeforecallingtoo11` preference domain for continuity; obsolete keys are ignored. The first changed save backs up the existing preferences. Custom text accepts `{recipient}` and the legacy `%@` placeholder. Clear a text field to restore its default.

Selected whitelist addresses are saved locally. Remove and re-add a contact if its number or email changes. With **All Recipients Must Match** disabled, one matching contact can exempt the whole recipient group.

## Scope

Protection applies to the supported outgoing actions in Phone, FaceTime, Contacts, system contact-card services, Messages and Apple Mail. It is not a system-wide guarantee. Siri, third-party apps, notification quick replies, scheduled sending and group-call joins have not been covered or verified.

Cancel leaves the action unsent. Backgrounding, dismissal, unavailable presentation, timeout or changed message recipients/draft cancels a pending action. System-classified emergency calls and dedicated SOS URLs bypass confirmation. If the system cannot classify an emergency call, its URL is forwarded rather than obstructed.

No phone numbers, email addresses or message bodies are written to diagnostic reports. Hook and decision reports are stored in the jailbreak's `/var/mobile/Library/Logs/AskBeforeCallingToo26-*.plist` files. Include the relevant report, action used and device details when [reporting an issue](https://github.com/sahinkaa/AskBeforeCallingToo26/issues).

## Removal

Uninstall **AskBeforeCalling Too 26** in Sileo and respring. Preferences are retained.

## Source and build

See [BUILD.md](BUILD.md) for the RootHide build instructions and [RESEARCH.md](RESEARCH.md) for implementation notes. The source archive includes the same source and verification tools used to build the release.
