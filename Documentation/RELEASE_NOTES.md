A native driver, and no site to fetch

**Version 1.0.0.** The application no longer wraps somebody else's web interface. It speaks the device protocol itself, draws its own screen, and on a normal launch fetches nothing from anywhere.

### What changed

- **The protocol is implemented here.** Frames, CRC16-Modbus, roles, stream slicing and field parsing in `NothingProtocol.swift`; a catalogue of 84 commands, 23 models and 63 identification records in `NothingCatalog.swift`, with capabilities and gesture layouts carried as data rather than branches in code. 42 of those commands have been confirmed against real hardware; the rest are derived and marked as such.
- **A native screen.** Three tabs — Sound, Headphones, Controls — covering noise cancellation and its strength, equaliser presets and bands, bass, spatial audio, gestures, codec, in-ear detection, low latency, personal sound, dual connection, find-my-device, battery and firmware. Russian and English, switched at runtime; light and dark follow the system or are pinned in the app.
- **A menu bar item.** Battery and listening mode without opening the window. A left click changes noise cancellation and its strength, a right click opens the rest. Closing the window hides it rather than quitting — the driver outlives its own display — and quitting by any route releases the Bluetooth channel, which the device grants to one program at a time.
- **The borrowed interface moved behind `--web`.** It still covers models and functions the native screen has not caught up on, and in that mode the app fetches it from the authors' deployment exactly as before. A normal launch does not.

### What did not change

No upstream file is in this repository or in the application bundle, and CI still fails the build if one appears. The licence is still AGPL-3.0 by choice: the protocol knowledge behind the native layer was derived from the AGPL-licensed source of [ear (web)](https://github.com/radiance-project/ear-web), and matching their licence is the honest answer to that.

### Before you file an issue

Only **Nothing Headphone (1)** has been verified against hardware. Every other model is carried as data read out of the upstream configuration and has never been in front of a device — if yours misbehaves, that is worth reporting here, with the log from `~/Library/Logs/ear-local.log`.
