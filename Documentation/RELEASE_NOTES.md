Headphones without a browser

**First release.** A native macOS application that controls Nothing and CMF headphones — noise cancellation, equaliser, gestures, battery, firmware — without Chromium, without Docker, without a local web server.

### What it does

- **Runs the ear (web) interface where it could never run before.** That driver reaches devices through the Web Serial API over Bluetooth SPP, and WebKit implements no such thing — which is why it demands Chromium 117+ and refuses to start anywhere else. This app keeps the interface untouched and hands it a transport of its own: a native `IOBluetooth` RFCOMM bridge behind a `navigator.serial` shim. The upstream JavaScript never learns that the port underneath is not a port.
- **Finds the right channel.** The headphones publish fifteen Bluetooth services, and the one macOS surfaces as `/dev/cu.*` is not the one that answers. The bridge locates the custom SPP service over SDP and opens its RFCOMM channel directly.
- **Survives idle disconnects.** Devices close a quiet channel. The bridge reopens it on demand and replays what you pressed, with a time limit so an hour-old command never lands on top of settings you have since changed from your phone.
- **Works offline.** The interface is fetched once from the authors' own deployment and kept on disk. Changing a listening mode needs no network.
- **Updates quietly.** On launch the local copy is compared against the live site by `Last-Modified` and size; a fresh one is downloaded when they differ, and exactly one copy is kept on disk.

### What it deliberately does not do

It bundles no upstream code. It adds no device support of its own — if the ear (web) project does not support your model, neither does this. It is not a fork and not a mirror; all device knowledge, and all credit for it, stays with [radiance-project/ear-web](https://github.com/radiance-project/ear-web).

### Before you file an issue

A control that does nothing, a model that is not recognised, an equaliser band that is wrong — that is upstream: [ear-web/issues](https://github.com/radiance-project/ear-web/issues). Issues here should be about the macOS side: the Bluetooth bridge, the window, signing, permissions, the updater.
