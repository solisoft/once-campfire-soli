# Frontend changes

The frontend is the reference's (`reference/app/javascript`, `reference/app/assets`, and the gem
assets copied byte-for-byte into `vendor/`, see `vendor/MANIFEST.md`). `bin/build-assets` puts
`overrides/` first on the load path, then applies the edits listed in its `PATCHES` table to
vendored files as it copies them, so `vendor/` stays identical to the gems.

| Change | Where | Why |
|---|---|---|
| `isProtocolSupported()` also accepts no subprotocol | `turbo.js` (Turbo's bundled Action Cable) and `actioncable.esm.js` (patched) | Soli's WebSocket upgrade does not echo `Sec-WebSocket-Protocol`, so browsers report the empty protocol; the messages are still `actioncable-v1-json`. |
| `ConnectionMonitor#isStale()` is false while the socket is open | same two files (patched) | A Soli app has no in-process timer to send Action Cable's 3-second pings, so silence on an open socket is not staleness. A closed socket still reconnects after `staleThreshold`. |
| `lib/autocomplete/base_autocomplete_handler.js` asks for JSON with an `Accept` header | `overrides/` | The reference passes `{ as: "json" }`, a `@rails/request.js` option, to plain `fetch`, so it gets HTML. Same fix as the Rust port. |
| `install-edge.svg` | `overrides/` | `pwa/_install_instructions` asks for it at the top level; the reference only has `external/install-edge.svg`. Same fix as the Rust port. |
