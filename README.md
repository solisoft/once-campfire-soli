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
bin/build-assets                       # copies the frontend into public/assets (needs python3)
cp .env.example .env                   # set SECRET_KEY_BASE and SOLI_SESSION_SECRET
soli db:migrate up
soli serve . --port 5011 --workers 8   # add --dev for hot reload
```

`bin/build-assets` does what `rails assets:precompile` does for the reference: it copies the
frontend's CSS, JavaScript, images and sounds from `reference/`, `vendor/` and `overrides/` into
`public/assets` under digested names (`application-1a2b3c4d.css`). `public/assets` is not in git, so
run it after a clone, and again whenever `overrides/` or the submodules change. It also rewrites
`app/helpers/asset_manifest.sl` and `app/services/asset_manifest.sl`, the tables that turn
`application.css` into its digested path.

Open `/first_run` to create the account. Behind Soli Proxy, `app.infos` serves it in production mode.

## Performance

On one machine, with the same data and the same load, Soli serves the room page 15% faster than the
Rust port, and the sidebar and the health check about twice as fast. The messages page is 9% slower,
search 22% slower and posting a message 35% slower. Soli's p99 latency is lower on every page. Without
compression the room page is even (3% slower), and the messages page, search and posting are 10%, 16%
and 32% slower.

**How it was measured**

- **Workloads:** the reference README's five, plus the `/up` health check, driven by its harness's
  load generator (`bench/loadgen`): 16 keep-alive clients signed in as david, 4 s per run after a 1 s
  warm-up, three runs. Every response is checked for a 200 and a body. Tables show the median run.
- **Machine:** rbuild2, an AMD Ryzen 9 9950X. Each app gets CPUs 8–11 (four physical cores, their SMT
  siblings idle) for itself and everything it uses: Soli with SoliDB and SoliKV, Rust with its
  in-process SQLite. The load generator gets CPUs 12–15. Runs during which another job used the
  machine were thrown away.
- **Versions:** Rust is [once-campfire-rust](https://github.com/basecamp/once-campfire-rust)
  `64f8635`, built from its own Dockerfile. Soli is `main` at `4b7ef013` (after 2.17.1, unreleased),
  with SoliDB 2.2.0 and SoliKV 0.4.3, all built with fat LTO and one codegen unit.
- **Compression:** the load generator asks for gzip, as the reference harness does, and every app
  compresses: the reference with `Rack::Deflater`, the Rust port with a cache of compressed pieces,
  this app with Soli's `SOLI_COMPRESS=gzip`, which keeps what it compressed. A second set of tables
  repeats every run without compression (`Accept-Encoding: identity`).
- **CPU per request** is user + system time of every process involved (Soli: app, SoliDB and SoliKV;
  Rust: its container), divided by the requests served.

### With gzip

| Requests per second | Rust | Soli | Soli vs Rust |
|---|---:|---:|---|
| Room page | 32.0k | 36.7k | 15% faster |
| Messages page | 33.5k | 30.5k | 9% slower |
| Sidebar¹ | 34.5k | 65.9k | **1.9× faster** |
| Search | 37.2k | 29.0k | 22% slower |
| Post a message | 9.0k | 5.9k | 35% slower |
| `/up` | 164k | 315k | **1.9× faster** |

| Per request | p99 Rust | p99 Soli | CPU Rust | CPU Soli | Size Rust | Size Soli |
|---|---:|---:|---:|---:|---:|---:|
| Room page | 1.42 ms | 0.66 ms | 103 µs | 113 µs | 24.1 KB | 20.9 KB |
| Messages page | 1.28 ms | 0.74 ms | 90 µs | 129 µs | 16.2 KB | 12.2 KB |
| Sidebar¹ | 1.39 ms | 0.38 ms | 102 µs | 62 µs | 5.8 KB | 2.3 KB |
| Search | 0.95 ms | 0.84 ms | 98 µs | 138 µs | 9.7 KB | 9.5 KB |
| Post a message | 4.34 ms | 4.90 ms | 358 µs | 659 µs | – | – |
| `/up` | 0.17 ms | 0.12 ms | 11 µs | 9 µs | – | – |

### Without compression

| Requests per second | Rust | Soli | Soli vs Rust |
|---|---:|---:|---|
| Room page | 24.3k | 23.5k | 3% slower |
| Messages page | 26.2k | 23.4k | 10% slower |
| Sidebar¹ | 34.5k | 65.9k | **1.9× faster** |
| Search | 32.8k | 27.5k | 16% slower |
| Post a message | 9.5k | 6.4k | 32% slower |
| `/up` | 168k | 316k | **1.9× faster** |

| Per request | p99 Rust | p99 Soli | CPU Rust | CPU Soli | Size Rust | Size Soli |
|---|---:|---:|---:|---:|---:|---:|
| Room page | 2.06 ms | 1.20 ms | 164 µs | 178 µs | 416 KB | 421 KB |
| Messages page | 1.80 ms | 1.10 ms | 147 µs | 182 µs | 384 KB | 389 KB |
| Sidebar¹ | 1.38 ms | 0.38 ms | 102 µs | 61 µs | 30.7 KB | 9.8 KB |
| Search | 1.10 ms | 0.88 ms | 113 µs | 154 µs | 150 KB | 151 KB |
| Post a message | 4.29 ms | 5.00 ms | 351 µs | 599 µs | – | – |
| `/up` | 0.16 ms | 0.13 ms | 10 µs | 10 µs | – | – |

¹ Not the same work. The load generator sends no `Turbo-Frame` header, so the Rust port, like Rails,
renders the sidebar inside the application layout; this app always answers with the frame alone,
which is what Rails renders for the `Turbo-Frame` request a browser makes.

The room page is about 420 KB of HTML uncompressed (every message carries its actions menu), as it is
in Rails. A post answers with the same turbo-stream on both sides (about 9.3 KB); the load
generator's byte count for Rust's is wrong, so the tables give none. `/up` is the framework's floor:
Soli answers it before any application code, Rust with the Rails health check page.

### Memory and startup

| Memory (PSS) and startup | Rust | Soli |
|---|---:|---:|
| Idle | 44 MiB | 272 MiB (app 187, SoliDB 58, SoliKV 27) |
| Busiest moment, gzip | 200 MiB | 521 MiB (app 362, SoliDB 156, SoliKV 29) |
| Busiest moment, no compression | 203 MiB | 411 MiB (app 250, SoliDB 162, SoliKV 28) |
| Cold start until `/up` answers | 68 ms (container start included) | 94 ms (SoliDB and SoliKV already up) |

Soli's app memory is mostly its eight workers, each with its own interpreter, loaded code and page
caches; fewer workers use less. With compression on, add the cache of compressed bodies (64 MB at most
by default, `SOLI_COMPRESS_CACHE_MB`).

### What the numbers rest on

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

### Behind Soli Proxy

Compressing in front of the app instead does not work at this size. Measured with Soli 2.15.3 behind
Soli Proxy with the proxy's own compression on, which deflates every response afresh: the room page
falls to 3,190 req/s (the proxy spends about 1 ms of CPU per request on it), the messages page to
4,540 and search to 6,749. With `SOLI_COMPRESS`, the proxy passes the encoded response through. Even
uncompressed, the proxy's hop costs about 10 µs of CPU per request, more than Soli's whole `/up`
(7 µs; 140,319 req/s through it).

### Reproducing

These figures compare two implementations on one machine. The reference README's table was measured on
another (an AMD Ryzen AI MAX+ 395) and cannot be read against them. Action Cable throughput and
many-client memory were not measured.

With a seed from the Rust port (`parity/bin/seed build default`) and the loadgen built
(`cd bench/loadgen && cargo build --release`):

```sh
ALL="room_show messages_page sidebar search post_message up"
bench/run      --seed SEED --loadgen LOADGEN --workers 8 --reps 3 --compress --only "$ALL"   # this app, gzip
bench/run-rust --seed SEED --loadgen LOADGEN --image campfire-rust:bench --reps 3 --only "$ALL"
bench/run      --seed SEED --loadgen LOADGEN --workers 8 --reps 3 --gzip 0 --only "$ALL"     # no compression
bench/run-rust --seed SEED --loadgen LOADGEN --image campfire-rust:bench --reps 3 --gzip 0 --only "$ALL"
bench/run      --seed SEED --loadgen LOADGEN --workers 8 --reps 3 --proxy PATH/TO/soli-proxy  # behind the proxy
```

`bench/run` starts its own SoliDB and SoliKV on fresh data and imports the seed (and, with `--proxy`,
a Soli Proxy with compression on, on the same CPUs); both scripts pin every process, record CPU per
request (user and system), memory (RSS, anonymous, PSS) and cold start, and write raw results to
`bench/results/`. Set `BENCH_DB_PORT`, `BENCH_KV_PORT` or `BENCH_APP_PORT` when the default ports
(6799, 6899, 5299) are taken. The rbuild2 results: Soli in `bench/results/rbuild2-20261007/`
(`soli-gzip`, `soli-identity`); Rust, and the earlier Soli 2.15.3 and proxy runs, in
`bench/results/rbuild2-20261005/` (`rust-gzip`, `rust-identity`, `soli-gzip`, `soli-identity`,
`soli-proxy`, `soli-proxy-up`).

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
