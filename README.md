# FolderLock

Password-protect any file or folder on macOS, right from Finder.

```
report.pdf       →  report.pdf.locked        (file)
Photos/          →  Photos.locked            (folder)
```

Right-click → **Lock with FolderLock** → set a password. Double-click the `.locked` file to restore. Encryption is AES-256-GCM with PBKDF2-SHA256 (200k iterations). Wrong password fails cleanly with no data loss.

---

## Why

macOS has no built-in way to right-click a folder and set a password on it. Disk Utility can make encrypted `.dmg` containers, but that's not a normal folder. FolderLock fills the gap with a native, lightweight, free tool.

- One `.locked` file you can move, copy, email, or back up
- No mounts, vaults, or background daemons
- Works on any file type and any folder

## Features

- Native macOS app (Swift + SwiftUI), macOS 13+
- Finder right-click integration via Finder Sync Extension
- AES-256-GCM with per-item random salt + nonce (authenticated encryption)
- PBKDF2-HMAC-SHA256 key derivation (200,000 iterations)
- Drag-and-drop window for batch lock/unlock
- Double-click `.locked` files to unlock
- URL scheme (`folderlock://lock?path=...`) for Shortcuts and scripts

---

## Setup

### Requirements

- macOS 13 (Ventura) or later
- **Full Xcode 15+** (Command Line Tools alone aren't enough)
- Free Apple ID (Personal Team signing is fine)
- [Homebrew](https://brew.sh) and [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Build

```bash
git clone https://github.com/SuryaKiran434/folderlock-mac
cd folderlock-mac
brew install xcodegen
xcodegen
open FolderLock.xcodeproj
```

In Xcode:

1. Click the **FolderLock** project in the sidebar.
2. Under **TARGETS**, select **FolderLock** → **Signing & Capabilities** tab → set your **Team**.
3. Repeat for the **FolderLockFinder** target (same Team).
4. Press **⌘R** to build and run.

### Enable the Finder extension

After first launch, quit the app (⌘Q), then:

- **macOS 13**: System Settings → Privacy & Security → Extensions → Added Finder Extensions → toggle **FolderLockFinder** on.
- **macOS 14+**: System Settings → General → Login Items & Extensions → Finder Extensions → toggle **FolderLockFinder** on.

Right-click any file in Finder. You should see **Lock with FolderLock**.

---

## Usage

| Action | How |
|---|---|
| Lock a file or folder | Right-click in Finder → **Lock with FolderLock** |
| Unlock | Right-click `.locked` file → **Unlock with FolderLock**, or double-click it |
| Batch lock/unlock | Drag items into the FolderLock window |
| From scripts | Open `folderlock://lock?path=/abs/path` |

After locking, the original file or folder is removed and replaced by a single `.locked` file.

---

## How it works

```
FolderLock.app  ◄── URL scheme ── FolderLockFinder.appex  (Finder right-click)
       │
       └── uses ──► FolderLockCore.framework  (AES-GCM + PBKDF2 + format)
```

- The Finder extension does no crypto — it just builds `folderlock://` URLs and asks the main app to handle them.
- The main app reads the file, derives a key from the password, encrypts with AES-256-GCM, writes `.locked`, deletes the original.
- Unlock reverses it. GCM auth tags detect wrong passwords (and any tampering) before anything is written.

### `.locked` file layout

`LOCK` magic + version + isDirectory flag + PBKDF2 iterations + 16-byte salt + 12-byte nonce + original filename + ciphertext + 16-byte GCM tag. Folders are zipped before encryption.

---

## Project structure

```
FolderLock/
├── project.yml                # XcodeGen config
├── Sources/
│   ├── Core/                  # Crypto framework (no UI)
│   ├── App/                   # SwiftUI main app
│   └── FinderExtension/       # Right-click menu provider
└── README.md
```

`FolderLock.xcodeproj/`, generated Info.plists, and entitlements are git-ignored — every developer regenerates them with `xcodegen`.

---

## Future scope

These are planned improvements, roughly in priority order:

**Adoption**
- Signed, notarized `.dmg` release on GitHub (so users don't need Xcode)
- Sparkle-based auto-updater
- Mac App Store distribution
- Custom padlock icon on `.locked` files + Quick Look preview

**Security and recovery**
- Touch ID / Face ID unlock via Keychain + Secure Enclave
- One-time recovery key (BIP39 phrase) shown at first lock for forgotten-password recovery
- Optional iCloud Keychain sync of recovery keys across your Apple devices
- Argon2id key derivation (stronger GPU resistance than PBKDF2)
- Wrong-password rate limiting with exponential backoff
- Auto-relock on screen lock or sleep

**Scale and performance**
- Streaming chunked encryption for large files (currently the whole file is loaded into memory)
- Background processing with progress bar
- "Locked vault" folder mode: anything dropped in is auto-locked

**Cross-platform**
- iOS companion app to open `.locked` files from iCloud Drive / Files
- Web-based decryptor (single HTML page using WebCrypto) for one-off shared files
- CLI tool (`folderlock lock /path -p pw`) for terminal use

**Polish**
- Onboarding tour on first launch
- Localization (Spanish, French, German, Portuguese, Japanese)
- VoiceOver and full keyboard navigation
- Password strength meter (zxcvbn)
- In-app help and FAQ

---

## Security caveats

- **No password recovery yet.** Forget the password = lose the data. Back up important files before locking.
- **Original is deleted** after successful lock. Make a copy first if you're unsure.
- Use strong, unique passwords (or a password manager). PBKDF2 slows brute-force but doesn't save weak passwords.
- The main app is intentionally **not** sandboxed so it can read/write arbitrary paths. The Finder extension is sandboxed (required by macOS).
- Pair with **FileVault** (System Settings → Privacy & Security) for full-disk protection.

## Troubleshooting

**Build fails right after `xcodegen`** — set a **Team** on both `FolderLock` and `FolderLockFinder` targets in Xcode → Signing & Capabilities.

**"Lock with FolderLock" missing from right-click menu** — enable **FolderLockFinder** in System Settings → Extensions → Finder Extensions, then `killall Finder`.

**"Operation not permitted" on certain folders** — grant FolderLock.app **Full Disk Access** in System Settings → Privacy & Security.

**Re-running `xcodegen` wipes the Team setting** — add `DEVELOPMENT_TEAM: YOUR_TEAM_ID` to `settings.base` in `project.yml`.

---

## License

[MIT](LICENSE)
