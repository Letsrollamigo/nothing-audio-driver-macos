<p align="center">
  <img src="./assets/readme/hero.svg" width="100%"
       alt="Unofficial driver for Nothing audio devices — a native macOS driver for Nothing and CMF headphones, with its own implementation of the device protocol.">
</p>

<p align="right">🇬🇧 English · 🇷🇺 <a href="Documentation/README.ru.md">Читать по-русски</a></p>

<p align="center">
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-13%2B-1B2A4E.svg" alt="Requires macOS 13 or later"></a>
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6-FF6A3D.svg" alt="Built with Swift 6"></a>
  <img src="https://img.shields.io/badge/interface-native-1B2A4E.svg" alt="Native SwiftUI interface">
  <img src="https://img.shields.io/badge/bundled%20upstream%20code-none-2E7D32.svg" alt="No upstream code is bundled in this repository">
  <a href="https://github.com/Letsrollamigo/nothing-audio-driver-macos/actions/workflows/build.yml"><img src="https://github.com/Letsrollamigo/nothing-audio-driver-macos/actions/workflows/build.yml/badge.svg" alt="CI status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-AGPL--3.0-6E7686.svg" alt="AGPL-3.0 license"></a>
</p>

**Unofficial driver for Nothing audio devices** controls Nothing and CMF headphones from macOS — noise cancellation and its strength, equaliser presets and bands, bass, spatial audio, gestures, codec, battery, in-ear detection, dual connection, find-my-device — in a native window, with a menu bar item for the things you reach for without looking.

It downloads nothing, serves nothing over localhost and opens no browser. The protocol is implemented here, in Swift: frames, CRC16, the command catalogue, per-model capabilities and firmware bands.

## Where this came from

The device protocol was not published by anyone. It was learned by reading the source of [ear (web)](https://github.com/radiance-project/ear-web) — an excellent open web driver, AGPL-3.0, deployed at [earweb.bttl.xyz](https://earweb.bttl.xyz) — and then checked against real hardware, frame by frame.

Earlier versions of this project were a shell around that interface: they took the web driver as-is and handed it the transport WebKit lacks, because the site speaks **Web Serial over Bluetooth SPP** and no WebKit view implements it. Version 1.0.0 no longer needs it. The interface is ours, the protocol layer is ours, and nothing is fetched from their deployment on a normal launch.

Their interface is still one launch flag away — `--web` — because it covers models and functions the native screen has not caught up on. Used that way, and only then, the app fetches the interface from the authors' own deployment onto your machine, exactly as before.

**No upstream file is in this repository or in the application bundle**, and CI fails the build if one appears. The licence here is AGPL-3.0 by choice, not by obligation — see [Licence](#licence).

## What it does

**Speaks the protocol itself.** A catalogue of 84 commands, 23 models and 63 identification records, with capabilities and gesture layouts carried as data rather than branches in code. 42 of those commands have been confirmed against real hardware; the rest are derived from the upstream source and marked as such in the catalogue.

**A native screen.** Three tabs — Sound, Headphones, Controls — laid out for a fixed window, in Russian or English, switched at runtime. Light and dark follow the system, or are pinned in the app.

**A menu bar item.** Battery and listening mode without opening the window; a left click changes noise cancellation and its strength, a right click opens the rest.

**A real Bluetooth transport.** The app locates the device's custom SPP service over SDP, opens the RFCOMM channel and reassembles protocol frames itself. When headphones drop an idle channel, it reopens it silently and replays what you pressed. Quitting always releases the channel — the device grants it to one program at a time.

## What it does not do

It supports no device that upstream's configuration does not describe. Only **Nothing Headphone (1)** has been verified against hardware — every other model is carried as data read out of the upstream source and has never been in front of a device. Reports about a specific model are welcome; so are captures.

It is not signed by Apple. Releases are ad-hoc signed and not notarised.

## Getting it

| Channel | What you get | Trade-off |
|---|---|---|
| **[Releases](https://github.com/Letsrollamigo/nothing-audio-driver-macos/releases/latest)** | A ready `.app`, built by CI from tagged source | Ad-hoc signed, so macOS asks for Bluetooth permission again after every update, and the bundle needs `xattr -d com.apple.quarantine` once |
| **Building from source** | The same app signed with your own certificate | Two minutes of setup — and the Bluetooth permission then survives every rebuild |

## Requirements

- macOS 13 or later, Apple Silicon or Intel
- Xcode command line tools (`swiftc`, `codesign`, `iconutil`)
- Headphones already paired in System Settings → Bluetooth
- A Nothing or CMF device

## Building from source

```bash
git clone https://github.com/Letsrollamigo/nothing-audio-driver-macos.git
cd nothing-audio-driver-macos
./build.sh
open "build/Unofficial driver for Nothing audio devices.app"
```

That is the whole build. No package manager, no Xcode project, no dependencies — `build.sh` compiles the sources, assembles a universal bundle and signs it.

| Command | What it does |
|---|---|
| `./build.sh` | Build into `build/` |
| `./build.sh --test` | 210 checks of the protocol and the path rules; no hardware needed |
| `./build.sh --install` | Build and copy into `/Applications` |
| `SITE_SRC=/path/to/site ./build.sh` | Bundle a copy of the web interface you already have, for `--web` |
| `SITE_SRC=none ./build.sh` | Build without one (the default when nothing is found) |

### Signing, and why it matters

macOS gates Bluetooth behind TCC, and TCC identifies an application by its code signature. With the default ad-hoc signature the hash changes on every build, so **the system asks for Bluetooth permission again after every rebuild**. A self-signed certificate fixes that permanently:

1. Keychain Access → Certificate Assistant → Create a Certificate
2. Name `ear-local-dev`, identity type **Self Signed Root**, certificate type **Code Signing** — the default type is S/MIME and will not work
3. Build with it:

```bash
CODESIGN_ID=ear-local-dev ./build.sh --install
```

Grant Bluetooth once on first launch; the permission then survives rebuilds, renames and moving the app to `/Applications`.

## How it's built

| Part | File | Job |
|---|---|---|
| Codec | `Sources/NothingProtocol.swift` | Frame, CRC16-Modbus, roles, stream slicing, field parsing |
| Catalogue | `Sources/NothingCatalog.swift` | Commands, models, capabilities, gesture layouts — generated, not hand-edited |
| Screen | `Sources/NativeScreen.swift` | Window, tabs, menu bar item, transport for the views |
| Strings | `Sources/Localisation.swift` | Russian and English in one table, switched at runtime |
| Bridge | `Sources/main.swift` (`SerialBridge`) | SDP lookup, RFCOMM channel, frame reassembly, reconnect, outbox |

The catalogue is generated from the upstream configuration by a script that stays on the author's machine: it needs a local copy of their site, and its output — numbers, not code — is what lands here.

Two more files serve `--web` only: `Sources/shim.js`, nine members of the Web Serial API on top of `webkit.messageHandlers`, and `Sources/SiteUpdater.swift`, which mirrors and prunes copies of the interface. That path is described in [Documentation/ARCHITECTURE.md](Documentation/ARCHITECTURE.md), which predates the native layer and covers the shell, the shim and the transport only.

## Flags

| Flag | What it does |
|---|---|
| `--web` | The borrowed web interface instead of the native screen |
| `--dark`, `--light` | Pin the appearance regardless of the system |
| `--force-update` | Fetch a fresh copy of the web interface without asking |

The log — every frame in both directions — is at `~/Library/Logs/ear-local.log`.

## Known constraints

**First run needs freshly connected headphones.** The identification channel that reports the device model is one-shot: the device offers it only right after connecting. The app caches the answer per device address and reuses it afterwards, but the very first launch on a given device must catch it live. Without the model, capability-dependent controls — noise cancellation strength, the gesture layout — do not appear.

**One verified model.** See above: everything beyond Nothing Headphone (1) is derived knowledge.

**Releases are not notarised.** There is no Apple Developer account behind this project, so a downloaded build needs `xattr -d com.apple.quarantine` once, and its ad-hoc signature makes macOS re-ask for Bluetooth after every update. Building locally with your own certificate avoids both.

## Licence

[AGPL-3.0](LICENSE), the same licence as [ear (web)](https://github.com/radiance-project/ear-web).

That is a deliberate choice rather than an inherited obligation. This repository ships none of their code, so nothing compelled it — but the protocol knowledge behind the native layer was derived from their AGPL-licensed source, and matching their licence is the honest answer to that. The authors were notified: [radiance-project/ear-web#172](https://github.com/radiance-project/ear-web/issues/172). See [NOTICE.md](NOTICE.md).

Nothing and CMF are trademarks of Nothing Technology Limited. This project is unofficial and unaffiliated.
