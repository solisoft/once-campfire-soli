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

Soli 2.15+, SoliDB 2.2+ and SoliKV. Each one has an installer that puts the latest release binary
in `~/.local/bin` (add `--system` after `sh -s --` for `/usr/local/bin`), on Linux and macOS:

```sh
curl -sSL https://raw.githubusercontent.com/solisoft/soli_lang/main/install.sh | sh
curl -sSL https://raw.githubusercontent.com/solisoft/solidb/main/install.sh | sh
curl -sSL https://raw.githubusercontent.com/solisoft/kv/main/install.sh | sh
soli --version && solidb --version && solikv --version
```

`soli update` and `solidb update` upgrade in place later.

Start SoliDB and SoliKV in their own directory, not the app's: SoliDB reads a `.env` in its working
directory, and the app's `SOLIDB_HOST` (a URL) would become its bind address.

```sh
mkdir -p ~/campfire-data && cd ~/campfire-data
SOLIDB_ADMIN_PASSWORD=admin solidb --port 6745 --data-dir ./solidb --daemon
solikv --bind 127.0.0.1 --port 6379 --rest-port 0 --dir ./solikv &
```

`SOLIDB_ADMIN_PASSWORD` sets the admin password when the data directory is first created, to match
`SOLIDB_PASSWORD` in `.env.example`; without it SoliDB generates one and writes it to
`solidb/.admin_password`. SoliKV listens on 127.0.0.1 only, so the app points at that address
(`SOLIKV_RESP_HOST`): `localhost` can resolve to `::1`. The database itself is created by the first
`soli db:migrate`.

Then, from the app's checkout:

```sh
git submodule update --init
bin/build-assets                       # public/assets and the asset manifests
cp .env.example .env                   # set SECRET_KEY_BASE and SOLI_SESSION_SECRET
soli db:migrate up
soli serve . --port 5011 --workers 8   # add --dev for hot reload
```

Open `/first_run` to create the account. Behind Soli Proxy, `app.infos` serves it in production mode.

## Performance

The five HTTP workloads of the reference README and its health check, measured with its harness's load
generator (`bench/loadgen`: keep-alive clients signed in as david, every response checked for a 200
and a body) on the same parity seed as the other ports.

Like the reference harness, the load generator asks for gzip, and Campfire compresses: the reference
installs `Rack::Deflater` in its `config.ru`, and the Rust port does the same with a cache of
compressed pieces. This app uses Soli's response compression (`SOLI_COMPRESS=gzip`), which keeps what
it compressed. A second table repeats every run with `Accept-Encoding: identity`, with neither side
compressing.

Both apps on rbuild2, an AMD Ryzen 9 9950X, each given CPUs 8–11 (four physical cores, their SMT
siblings idle) for itself and everything it uses: Soli with SoliDB and SoliKV, Rust with its in-process
SQLite. The load generator gets CPUs 12–15. 16 concurrent clients, 4 s per run after a 1 s warm-up,
three runs, direct listeners. Every thread's affinity was checked before measuring, and runs during
which another job used the machine were thrown away. Rust is
[once-campfire-rust](https://github.com/basecamp/once-campfire-rust) `64f8635`, built from its own
Dockerfile. Soli 2.15.3 with its response compression (`SOLI_COMPRESS`, not in a release yet), SoliDB
2.2.0 and SoliKV, built from their sources with their manifests' release profiles (fat LTO, one
codegen unit), not a build server's faster-to-compile ThinLTO.

**gzip** (`Accept-Encoding: gzip`, as the reference harness sends):

| Requests/sec, median of 3 (range) | Rust | Soli | Soli / Rust |
|---|---:|---:|---:|
| Room page | 31,992 (31,974–35,914) | 37,937 (37,866–38,104) | 1.19× |
| Messages page | 33,538 (32,736–38,945) | 31,906 (31,639–32,078) | 0.95× |
| Sidebar¹ | 34,539 (33,963–35,374) | 64,924 (53,545–65,041) | 1.88× |
| Search | 37,159 (36,096–37,222) | 30,751 (30,614–30,784) | 0.83× |
| Post a message | 9,006 (8,610–9,457) | 5,853 (5,737–6,111) | 0.65× |
| `/up` | 164,046 (162,911–165,187) | 315,909 (308,014–320,101) | 1.93× |

| p99 latency / CPU per request / body sent | Rust | Soli (app + SoliDB + SoliKV) |
|---|---:|---:|
| Room page | 1.42 ms / 91 µs / 24.1 KB | 0.64 ms / 95 µs / 20.9 KB |
| Messages page | 1.28 ms / 78 µs / 16.2 KB | 0.71 ms / 104 µs / 12.2 KB |
| Sidebar¹ | 1.39 ms / 90 µs / 5.8 KB | 0.38 ms / 52 µs / 2.3 KB |
| Search | 0.96 ms / 82 µs / 9.7 KB | 0.80 ms / 116 µs / 9.5 KB |
| Post a message | 4.34 ms / 283 µs | 5.23 ms / 588 µs |
| `/up` | 0.17 ms / 8 µs | 0.12 ms / 7 µs |

**identity** (`bench/run --gzip 0`, `bench/run-rust --gzip 0`):

| Requests/sec, median of 3 (range) | Rust | Soli | Soli / Rust |
|---|---:|---:|---:|
| Room page | 24,279 (23,898–26,093) | 23,771 (23,706–23,888) | 0.98× |
| Messages page | 26,187 (25,901–29,069) | 24,038 (24,024–24,101) | 0.92× |
| Sidebar¹ | 34,476 (34,375–35,352) | 64,134 (64,083–64,198) | 1.86× |
| Search | 32,762 (30,873–32,899) | 29,762 (29,591–29,862) | 0.91× |
| Post a message | 9,454 (9,443–9,460) | 6,460 (6,349–6,767) | 0.68× |
| `/up` | 167,531 (165,748–168,005) | 312,865 (311,842–313,140) | 1.87× |

| p99 latency / CPU per request / body sent | Rust | Soli (app + SoliDB + SoliKV) |
|---|---:|---:|
| Room page | 2.11 ms / 121 µs / 416 KB | 1.20 ms / 136 µs / 421 KB |
| Messages page | 1.80 ms / 107 µs / 384 KB | 1.08 ms / 134 µs / 389 KB |
| Sidebar¹ | 1.36 ms / 90 µs / 30.7 KB | 0.39 ms / 53 µs / 9.8 KB |
| Search | 1.10 ms / 90 µs / 150 KB | 0.81 ms / 119 µs / 151 KB |
| Post a message | 4.26 ms / 280 µs | 4.69 ms / 526 µs |
| `/up` | 0.16 ms / 8 µs | 0.13 ms / 7 µs |

¹ Not the same work. The load generator sends no `Turbo-Frame` header, so the Rust port, like Rails,
renders the sidebar inside the application layout (30.7 KB); this app always answers with the frame
alone (9.8 KB), which is what Rails renders for the `Turbo-Frame` request a browser makes.

The room page is 420 KB of HTML (every message carries its actions menu), as it is in Rails. A post
answers with the same turbo-stream on both sides (about 9.3 KB); the load generator's byte count for
Rust's is wrong, so the table gives none. `/up` is the framework's floor: Soli answers it before any
application code, Rust with the Rails health check page. An earlier version of this table gave Rust
4,333 req/s for posting, from a run that later runs did not reproduce (8,610–9,460).

| Memory and startup | Rust | Soli |
|---|---:|---:|
| Idle, PSS | 44 MiB | 272 MiB (app 187, SoliDB 58, SoliKV 27) |
| Peak during the workloads, gzip, PSS | 200 MiB | 503 MiB (app 355, SoliDB 159, SoliKV 29) |
| Peak during the workloads, identity, PSS | 203 MiB | 407 MiB (app 251, SoliDB 164, SoliKV 28) |
| Cold start until `/up` answers | 68 ms (container start included) | 102 ms (SoliDB and SoliKV already up) |

Soli's app memory is mostly its eight workers, each with its own interpreter, loaded code and page
caches; fewer workers use less. With compression on, add the cache of compressed bodies (64 MB at most
by default, `SOLI_COMPRESS_CACHE_MB`), which also keeps the bodies it compressed alive.

What the numbers rest on:

- **Compressed pages are kept.** Soli gzips at level 6 (zlib's, so `Rack::Deflater`'s) and keeps the
  result in a cache its workers share. A room page's cached response is the same string from one
  request to the next and is found by its buffer; the messages page and search, joined per request,
  are found by a hash and compared byte for byte. Compression makes the large pages faster, not
  slower: moving 420 KB through the kernel cost more than finding 21 KB already compressed. Posting
  compresses every reply, since none repeats (about 60 µs).
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

Compressing in front of the app instead does not work at this size. Behind Soli Proxy with its own
compression on, which deflates every response afresh, the room page falls to 3,190 req/s (the proxy
spends about 1 ms of CPU per request on it), the messages page to 4,540 and search to 6,749; with
`SOLI_COMPRESS` the proxy passes the encoded response through. Even uncompressed, the proxy's hop
costs about 10 µs of CPU per request, more than Soli's whole `/up` (7 µs; 140,319 req/s through it).

These figures compare two implementations on one machine. The reference README's table was measured on
another (an AMD Ryzen AI MAX+ 395) and cannot be read against them; a run on a slower laptop is in
`bench/results/20261004-pinned/`. Action Cable throughput and many-client memory were not measured.

To reproduce, with a seed from the Rust port (`parity/bin/seed build default`) and the loadgen built
(`cd bench/loadgen && cargo build --release`):

```sh
ALL="room_show messages_page sidebar search post_message up"
bench/run      --seed SEED --loadgen LOADGEN --workers 8 --reps 3 --compress --only "$ALL"   # this app, gzip
bench/run-rust --seed SEED --loadgen LOADGEN --image campfire-rust:bench --reps 3 --only "$ALL"
bench/run      --seed SEED --loadgen LOADGEN --workers 8 --reps 3 --gzip 0 --only "$ALL"     # identity
bench/run-rust --seed SEED --loadgen LOADGEN --image campfire-rust:bench --reps 3 --gzip 0 --only "$ALL"
bench/run      --seed SEED --loadgen LOADGEN --workers 8 --reps 3 --proxy PATH/TO/soli-proxy  # behind the proxy
```

`bench/run` starts its own SoliDB and SoliKV on fresh data and imports the seed (and, with `--proxy`,
a Soli Proxy with compression on, on the same CPUs); both scripts pin every process, record CPU per
request (user + system, the system part on its own), memory (RSS, anonymous, PSS) and cold start, and
write raw results to `bench/results/`. The rbuild2 results are in `bench/results/rbuild2-20261005/`:
`soli-gzip`, `rust-gzip`, `soli-identity`, `rust-identity`, `soli-proxy` and `soli-proxy-up`; `soli`
and `rust` hold the runs of this README's previous version.

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
- **The sidebar outside a frame.** `/users/me/sidebar` always answers with the frame alone. Rails
  renders the application layout around it unless the request carries `Turbo-Frame`, as a browser's
  does.
- **Web Push** needs `VAPID_PUBLIC_KEY` and `VAPID_PRIVATE_KEY`; without them the queue is emptied.

## Third-party code

The frontend in `reference/`, the gem assets in `vendor/` and `bench/loadgen` are MIT-licensed by their
authors; their license files sit beside them.
