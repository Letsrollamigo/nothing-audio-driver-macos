# Architecture

Three pieces, none of which knows anything about headphones. All device
knowledge stays in the upstream interface; this repository only carries bytes
between it and the Bluetooth stack.

## The problem

The upstream interface reaches the device through the **Web Serial API over
Bluetooth SPP**:

```js
sppPort = await navigator.serial.requestPort({
    allowedBluetoothServiceClassIds: [SPP_UUID],
    filters: [{ bluetoothServiceClassId: SPP_UUID }],
});
```

WebKit implements neither Web Serial nor its Bluetooth option, which is why the
interface requires Chromium 117+ and refuses to start anywhere else. A wrapper
around a `WKWebView` therefore has to bring the transport with it.

## The shim

`Sources/shim.js` is injected at document start and defines `navigator.serial`
before any page script runs. The surface the interface actually uses is small —
`requestPort`, `getPorts`, and on the port `open`, `close`, `forget`, `opened`,
`getInfo`, `readable`, `writable`. Messages travel to the native side through
`webkit.messageHandlers` and back through `evaluateJavaScript`.

Two deliberate deviations from the specification, both to match how the
interface actually behaves:

- `writer.close()` does nothing. The interface takes a fresh writer for every
  frame and closes it; against a real `WritableStream` that would end the stream
  after the first write.
- `read()` resolves with an empty array rather than `undefined` when the stream
  ends. The interface reads `value.length` before checking `done`, so
  `undefined` throws and takes the session down with it.

## The bridge

`SerialBridge` in `Sources/main.swift` speaks `IOBluetooth`:

1. Find the paired device publishing the requested service UUID via SDP —
   the device exposes fifteen services, and the one macOS surfaces as
   `/dev/cu.*` is not the right one.
2. Open its RFCOMM channel and keep it.
3. Reassemble frames. The wire format is
   `55 60 01 <cmdLo> <cmdHi> <len> 00 <opID>` plus payload plus CRC16-Modbus,
   and RFCOMM freely splits and coalesces deliveries. The interface's parser
   assumes one whole frame per read, so the bridge cuts the stream on the length
   byte and hands over exactly one frame at a time.
4. Survive idle disconnects. The device closes a quiet channel; the bridge
   reopens it on demand, holds unsent frames in a small outbox with a time to
   live, and only tells the page the session ended when reconnection fails.

Identification runs over a second service that answers once, immediately after
the device connects, with seven bytes naming the model. The bridge caches that
answer per device address and replays it when the channel stays silent —
otherwise every launch after the first would fail to identify the headphones.

## Serving the interface

A `WKURLSchemeHandler` serves the local copy over a private `earlocal://`
scheme. Two details matter:

- Responses must be `HTTPURLResponse` with status 200. The interface checks
  `response.ok` when fetching its configuration, and a plain `URLResponse`
  reports status 0 — which silently disables half the controls.
- Paths are normalised component by component and checked for containment.
  `url.path` arrives percent-decoded, so `%2f` becomes a separator and a naive
  handler would read arbitrary files.

## Updating

`SiteUpdater` compares the local copy against the live site by `Last-Modified`
(recorded in `meta.json` at download time) and by size, mirrors the site into
`~/Library/Application Support/ear-local/site-<stamp>` when they differ, and
prunes everything else. A new copy replaces the old one only if it is complete —
at least 98% of the current file count and containing `index.html` — so a bad
network session cannot degrade a working installation.
