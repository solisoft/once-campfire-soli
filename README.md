# once-campfire-soli

[ONCE Campfire](https://github.com/basecamp/once-campfire) ported to [Soli](https://soli.solisoft.net),
on SoliDB and SoliKV. The Rails app it follows is pinned in `reference/`.

The frontend is the reference's (Turbo, Stimulus, Lexxy, importmap), served from the pinned sources and
gem assets; [OVERRIDES.md](OVERRIDES.md) lists the few changes. The server is new: Soli controllers and
views, Action Cable over Soli WebSockets, SoliDB for the data (fulltext search, blobs for uploads and
their variants), SoliKV for sessions, rate limits, Cable presence and the push queue.

It covers setup and invitations, sign-in and session transfers, account and user administration, open,
closed and direct rooms, messages with rich text and attachments, editing and deletion, boosts,
mentions, search, involvement and unread state, Action Cable presence, typing and live updates, bots
and webhooks, link previews, Web Push and the PWA files.

Data lives in SoliDB documents, not in the reference's SQLite schema, so an existing Campfire install
cannot be switched over as it is. `bin/import-seed` loads a parity seed (an SQLite database plus its
Active Storage tree) and shows how a migration would go.

## Running it

Soli 2.15+, SoliDB 2.2+ and SoliKV, then:

```sh
git submodule update --init
bin/build-assets                       # public/assets and the asset manifests
cp .env.example .env                   # set SECRET_KEY_BASE and SOLI_SESSION_SECRET
soli db:migrate up
soli serve . --port 5011 --workers 8   # add --dev for hot reload
```

Open `/first_run` to create the account. Behind Soli Proxy, `app.infos` serves it in production mode.

## Performance

The five HTTP workloads of the reference README, measured with its harness's load generator
(`bench/loadgen`: keep-alive clients signed in as david, every response checked for a 200 and a body)
on the same parity seed as the other ports.

Both apps on rbuild2, an AMD Ryzen 9 9950X, each given CPUs 8–11 (four physical cores, their SMT
siblings idle) for itself and everything it uses: Soli with SoliDB and SoliKV, Rust with its in-process
SQLite. The load generator gets CPUs 12–15. 16 concurrent clients, 4 s per run after a 1 s warm-up,
three runs, direct listeners without compression. Every thread's affinity was checked before measuring.
Rust is [once-campfire-rust](https://github.com/basecamp/once-campfire-rust) `64f8635`, built from its
own Dockerfile. Soli 2.15.3, SoliDB 2.2.0 and SoliKV built from their sources with their manifests'
release profiles (fat LTO, one codegen unit), not a build server's faster-to-compile ThinLTO.

| Requests/sec, median of 3 (range) | Rust | Soli | Soli / Rust |
|---|---:|---:|---:|
| Room page | 32,212 (31,819–36,072) | 23,910 (23,863–24,234) | 0.74× |
| Messages page | 33,599 (32,828–38,404) | 24,132 (24,062–24,284) | 0.72× |
| Sidebar | 34,609 (34,564–35,308) | 64,608 (64,534–64,733) | 1.87× |
| Search | 36,224 (35,670–36,861) | 30,074 (29,962–30,314) | 0.83× |
| Post a message | 4,333 (4,308–4,356) | 6,463 (6,346–6,774) | 1.49× |

| p99 latency / CPU per request | Rust | Soli (app + SoliDB + SoliKV) |
|---|---:|---:|
| Room page | 1.40 ms / 91 µs | 1.19 ms / 134 µs |
| Messages page | 1.24 ms / 78 µs | 1.07 ms / 134 µs |
| Sidebar | 1.36 ms / 90 µs | 0.38 ms / 52 µs |
| Search | 0.96 ms / 85 µs | 0.80 ms / 118 µs |
| Post a message | 0.31 ms / 234 µs | 4.34 ms / 528 µs |

The room page is 420 KB of HTML (every message carries its actions menu), as it is in Rails.

| Memory and startup | Rust | Soli |
|---|---:|---:|
| Idle, PSS | 44 MiB | 253 MiB (app 172, SoliDB 56, SoliKV 25) |
| Peak during the five workloads, PSS | 137 MiB | 405 MiB (app 242, SoliDB 165, SoliKV 30) |
| Cold start until `/up` answers | 62 ms (container start included) | 101 ms (SoliDB and SoliKV already up) |

Soli's app memory is mostly its eight workers, each with its own interpreter, loaded code and page
caches; fewer workers use less.

What the numbers rest on:

- **Message HTML is rendered once.** Each message keeps its rendered HTML (`html`, `html_key`), the way
  the reference caches `messages/_message` per record. SoliDB joins a page of it inside the query, and
  each worker keeps the last answer for a page under a signature SoliDB computes, so a repeated page
  costs a signature check, not a transfer.
- **Page chrome is rendered once per worker** with markers where the per-request values go (messages,
  CSRF token, the room's timestamp), then reassembled with string joins (`_render_cached_page`). The
  sidebar re-renders only when SoliDB says its data changed. A room page's whole response is kept per
  user and room (64 per worker) until anything it shows changes.
- **Posting is one SoliDB statement**: the message goes in with its HTML, the room is touched, and only
  the members who turn unread are written. Push notifications are queued in SoliKV and delivered by a
  job every couple of seconds.
- **Sessions are in SoliKV**, and each worker keeps a resolved session for `SESSION_CACHE_TTL_MS`
  (2 s by default; 0 turns it off), so most requests authenticate without a round trip. A sign-out,
  ban or deactivation handled by another worker takes up to that long to reach this one. The Rust port
  reads its in-process SQLite on every request instead.
- **SoliDB's native driver** (`SOLI_DB_DRIVER=1`, MessagePack over pooled connections) instead of
  HTTP/JSON.
- **Only indexes the planner uses.** SoliDB serves a room's pages from the `room_id` hash index and
  sorts in memory; it never uses a compound `(room_id, created_at)` index, so that one is gone.

These figures compare two implementations on one machine. The reference README's table was measured on
another (an AMD Ryzen AI MAX+ 395) and cannot be read against them; a run on a slower laptop is in
`bench/results/20261004-pinned/`. Action Cable throughput and many-client memory were not measured.

To reproduce, with a seed from the Rust port (`parity/bin/seed build default`) and the loadgen built
(`cd bench/loadgen && cargo build --release`):

```sh
bench/run      --seed SEED --loadgen LOADGEN --workers 8 --reps 3            # this app
bench/run-rust --seed SEED --loadgen LOADGEN --image campfire-rust:bench     # the Rust port
```

`bench/run` starts its own SoliDB and SoliKV on fresh data and imports the seed; both scripts pin
every process, record CPU per request, memory (RSS, anonymous, PSS) and cold start, and write raw
results to `bench/results/`. Results from rbuild2 are in `bench/results/rbuild2-20261005/`.

## Known differences

- **Storage.** SoliDB documents keyed by integer strings (the frontend `parseInt`s ids), times in
  epoch milliseconds, files as SoliDB blobs. Not the reference's SQLite schema.
- **Passwords.** Soli verifies Argon2, not bcrypt; `bin/import-seed` gives imported users an Argon2
  digest of the seed's password.
- **Search.** SoliDB fulltext with every term required, as FTS5 does, but without Porter stemming:
  "coffees" does not find "coffee".
- **Action Cable.** The server sends no pings (a Soli app has no in-process timer) and Soli does not
  echo the `actioncable-v1-json` subprotocol; the client is patched for both (OVERRIDES.md).
- **Load generator.** `bench/loadgen` adds an `Origin` header to same-origin requests, which Soli's
  forgery protection checks in place of `Sec-Fetch-Site`.
- **Web Push** needs `VAPID_PUBLIC_KEY` and `VAPID_PRIVATE_KEY`; without them the queue is emptied.

## Third-party code

The frontend in `reference/`, the gem assets in `vendor/` and `bench/loadgen` are MIT-licensed by their
authors; their license files sit beside them.
