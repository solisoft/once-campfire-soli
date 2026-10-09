# once-campfire-soli

[ONCE Campfire](https://github.com/basecamp/once-campfire) ported to [Soli](https://soli.solisoft.net),
on SQLite. The Rails app it follows is pinned in `reference/`.

The frontend is the reference's (Turbo, Stimulus, Lexxy, importmap), served from the pinned sources and
gem assets; [OVERRIDES.md](OVERRIDES.md) lists the few changes. The server is new: Soli controllers and
views, Action Cable over Soli WebSockets, and one SQLite file for everything the reference keeps in
SQLite and Redis: the data, FTS5 search, sessions, rate limits, Cable presence and the push queue.
Uploads and their variants are files beside it, as Active Storage's disk service keeps them.

It covers setup and invitations, sign-in and session transfers, account and user administration, open,
closed and direct rooms, messages with rich text and attachments, editing and deletion, boosts,
mentions, search, involvement and unread state, Action Cable presence, typing and live updates, bots
and webhooks, link previews, Web Push and the PWA files.

The tables are the app's own, not the reference's schema (string keys, times in epoch milliseconds, a
message's rich text, attachment and rendered HTML on its row), so an existing Campfire install cannot
be switched over as it is. `bin/import-seed` loads a parity seed (an SQLite database plus its Active
Storage tree) and shows how a migration would go.

## Running it

Soli 2.18.7+, which carries SQLite (3.53, with FTS5) inside its binary: nothing else to install or
start. Its installer puts the latest release binary in `~/.local/bin` (add `--system` after
`sh -s --` for `/usr/local/bin`), on Linux and macOS:

```sh
curl -sSL https://raw.githubusercontent.com/solisoft/soli_lang/main/install.sh | sh
soli --version
```

`soli update` upgrades it in place later.

Then, from the app's checkout:

```sh
git submodule update --init
bin/build-assets                       # copies the frontend into public/assets (needs python3)
cp .env.example .env                   # set SECRET_KEY_BASE and SOLI_SESSION_SECRET
soli db:create && soli db:migrate up   # storage/campfire.sqlite3, from DATABASE_URL
soli serve . --port 5011 --workers 8   # add --dev for hot reload
```

`bin/build-assets` does what `rails assets:precompile` does for the reference: it copies the
frontend's CSS, JavaScript, images and sounds from `reference/`, `vendor/` and `overrides/` into
`public/assets` under digested names (`application-1a2b3c4d.css`). `public/assets` is not in git, so
run it after a clone, and again whenever `overrides/` or the submodules change. It also rewrites
`app/helpers/asset_manifest.sl` and `app/services/asset_manifest.sl`, the tables that turn
`application.css` into its digested path.

Open `/first_run` to create the account, or load the parity seed:
`bin/import-seed PATH/TO/seed && soli db:seed . db/seeds/after_import.sl`. Behind Soli Proxy,
`app.infos` serves it in production mode. Back the database up with SQLite's `.backup` or
`VACUUM INTO` (a plain copy of a live WAL database can miss frames), and `storage/blobs` with it.

## Performance

On one machine, with the same data and the same load, Soli serves the room, messages and sidebar
pages 2.2 to 2.4 times as fast as the Rust port, search 1.6 times as fast, and the health check 1.7
times. Posting a message is 21% slower. Without compression the room page is even (+7%), as both
spend their time moving its 410 KB; the other pages keep their lead, and posting is 16% slower.

Both sides answer a page they have already rendered from a cache of whole responses, invalidated by
any commit to the database: the read workloads write nothing, so after the first request every one
of them is a cache hit, on both. The difference is what a hit costs: Rust authenticates and checks
room access before its lookup (25 to 30 µs of CPU); Soli answers from its server layer before any
Soli code runs (7 to 11 µs). With both caches off, the room and messages pages are even and search
is 30% slower in Soli (see [Without the response caches](#without-the-response-caches)).

**How it was measured**

- **Workloads:** the reference README's five, plus the `/up` health check, driven by its harness's
  load generator (`bench/loadgen`): 16 keep-alive clients signed in as david, 4 s per run after a 1 s
  warm-up, three runs. Every response is checked for a 200 and a body (no invalid response in any
  run). Tables show the median run.
- **Machine:** rbuild2, an AMD Ryzen 9 9950X. Each app gets CPUs 8–11 (four physical cores, their SMT
  siblings idle) for itself, its SQLite included; the load generator gets CPUs 12–15. Every run waited
  for the machine to be otherwise idle.
- **Versions:** Rust is [once-campfire-rust](https://github.com/basecamp/once-campfire-rust)
  `9872c1d` (2026-10-08), built from its own Dockerfile, its response cache on by default. Soli is the
  code of 2.18.7 (SQLite 3.53, the server's response cache, the SQLite writer changes described
  below), built from `main` before the release. Fat LTO and one codegen unit, 8 workers.
- **Compression:** the load generator asks for gzip, as the reference harness does, and every app
  compresses: the reference with `Rack::Deflater`, the Rust port with a cache of compressed pieces,
  this app with Soli's `SOLI_COMPRESS=gzip`, which keeps what it compressed. A second set of tables
  repeats every run without compression (`Accept-Encoding: identity`).
- **CPU per request** is user + system time of the app's process (Rust: its container), divided by
  the requests served.

### With gzip

| Requests per second | Rust | Soli | Soli vs Rust |
|---|---:|---:|---|
| Room page | 110.0k | 254.2k | **2.3× faster** |
| Messages page | 110.6k | 269.8k | **2.4× faster** |
| Sidebar¹ | 127.0k | 276.3k | **2.2× faster** |
| Search | 127.2k | 202.2k | **1.6× faster** |
| Post a message | 8.07k | 6.40k | 21% slower |
| `/up` | 164.1k | 278.2k | **1.7× faster** |

| Per request | p99 Rust | p99 Soli | CPU Rust | CPU Soli | Size Rust | Size Soli |
|---|---:|---:|---:|---:|---:|---:|
| Room page | 0.54 ms | 0.11 ms | 30 µs | 7 µs | 23.6 KB | 20.4 KB |
| Messages page | 0.58 ms | 0.10 ms | 31 µs | 7 µs | 15.8 KB | 11.9 KB |
| Sidebar¹ | 0.48 ms | 0.10 ms | 26 µs | 7 µs | 5.7 KB | 2.2 KB |
| Search | 0.48 ms | 0.27 ms | 26 µs | 11 µs | 9.4 KB | 9.3 KB |
| Post a message | 4.71 ms | 9.59 ms | 404 µs | 373 µs | 1.9 KB | 1.9 KB |
| `/up` | 0.20 ms | 0.21 ms | 12 µs | 12 µs | – | – |

### Without compression

| Requests per second | Rust | Soli | Soli vs Rust |
|---|---:|---:|---|
| Room page | 46.3k | 49.6k | 7% faster |
| Messages page | 45.6k | 87.0k | **1.9× faster** |
| Sidebar¹ | 121.3k | 271.7k | **2.2× faster** |
| Search | 86.4k | 135.9k | **1.6× faster** |
| Post a message | 8.04k | 6.76k | 16% slower |
| `/up` | 158.1k | 281.4k | **1.8× faster** |

| Per request | p99 Rust | p99 Soli | CPU Rust | CPU Soli | Size Rust | Size Soli |
|---|---:|---:|---:|---:|---:|---:|
| Room page | 1.67 ms | 3.08 ms | 102 µs | 127 µs | 406 KB | 411 KB |
| Messages page | 1.53 ms | 0.42 ms | 102 µs | 39 µs | 375 KB | 380 KB |
| Sidebar¹ | 0.51 ms | 0.10 ms | 27 µs | 7 µs | 29.9 KB | 9.5 KB |
| Search | 0.72 ms | 0.21 ms | 42 µs | 15 µs | 146 KB | 148 KB |
| Post a message | 4.74 ms | 9.44 ms | 412 µs | 323 µs | – | – |
| `/up` | 0.19 ms | 0.21 ms | 13 µs | 12 µs | – | – |

¹ Not the same work. The load generator sends no `Turbo-Frame` header, so the Rust port, like Rails,
renders the sidebar inside the application layout; this app always answers with the frame alone,
which is what Rails renders for the `Turbo-Frame` request a browser makes.

The room page is about 410 KB of HTML uncompressed (every message carries its actions menu), as it is
in Rails: without compression, moving it through the kernel is most of what both sides do. A post
answers with the same turbo-stream on both sides; the load generator counts Rust's as 1.9 KB.
`/up` is the framework's floor: Soli answers it before any application code, Rust with the Rails
health check page.

### Without the response caches

Both caches off (`SOLI_RESPONSE_CACHE_MB=0`, `CAMPFIRE_RESPONSE_CACHE_MB=0`; the fragment caches,
which the reference has too, stay on), so every request does the work: authentication, queries,
the page. Same machine, same load. The room and messages pages are even, search is 30% slower in
Soli, posting 19% slower:

| Requests per second, gzip | Rust | Soli | Soli vs Rust |
|---|---:|---:|---|
| Room page | 30.0k | 29.7k | even |
| Messages page | 31.6k | 33.2k | 5% faster |
| Sidebar¹ | 32.9k | 38.4k | 17% faster |
| Search | 36.1k | 25.3k | 30% slower |
| Post a message | 8.02k | 6.51k | 19% slower |

| Per request, gzip | p99 Rust | p99 Soli | CPU Rust | CPU Soli |
|---|---:|---:|---:|---:|
| Room page | 1.58 ms | 0.87 ms | 113 µs | 145 µs |
| Messages page | 1.45 ms | 0.81 ms | 97 µs | 131 µs |
| Sidebar¹ | 1.48 ms | 0.59 ms | 107 µs | 118 µs |
| Search | 1.00 ms | 1.01 ms | 99 µs | 167 µs |
| Post a message | 4.69 ms | 9.63 ms | 415 µs | 381 µs |

Without compression: room page 22.9k / 23.1k, messages page 24.5k / 25.4k, sidebar 32.9k / 39.1k,
search 30.1k / 24.4k, posting 8.06k / 6.80k (Rust / Soli). The response caches, then, are where the
2.2–2.4× of the first tables comes from: what one hit costs, not what a page costs.

### Memory and startup

| Memory (PSS) and startup | Rust | Soli |
|---|---:|---:|
| Idle | 45 MiB | 182 MiB |
| Busiest moment, gzip | 213 MiB | 359 MiB |
| Busiest moment, no compression | 208 MiB | 252 MiB |
| Cold start until `/up` answers | 80 ms (container start included) | 41 ms |

Soli's memory is mostly its eight workers, each with its own interpreter, loaded code and page
caches; fewer workers use less. Add the server's caches: kept responses (64 MB at most,
`SOLI_RESPONSE_CACHE_MB`) and, with compression on, compressed bodies (64 MB at most,
`SOLI_COMPRESS_CACHE_MB`).

### What the numbers rest on

- **Whole responses are kept by the server.** The room, messages, sidebar and search actions mark
  their response `Soli-Response-Cache: 15` (`_keep` in ApplicationController). Soli then keeps it,
  keyed by the request line and every request header (cookies included, so only the same session gets
  it back), and answers the same request again before any Soli code runs while SQLite's
  `PRAGMA data_version` has not moved: any commit, from any worker, retires every entry. That is the
  Rust and C ports' response cache, which also invalidate on any commit and keep a page 15 s.
- **Compressed pages are kept.** Soli gzips at level 6 (zlib's, so `Rack::Deflater`'s) and keeps the
  result, found by the body's buffer: a kept response is compressed once.
- **Message HTML is rendered once.** Each message keeps its rendered HTML (`html`, `html_key`), the way
  the reference caches `messages/_message` per record. A page's query reads keys and `html_key`
  only (a message's big columns come last in its row), and joins the HTML only when the worker's last
  answer for that page is stale.
- **Page chrome is rendered once per worker** with markers where the per-request values go (messages,
  CSRF token, the room's timestamp), then reassembled with string joins (`_render_cached_page`).
- **Posting is three statements**, as Rails makes them: the message (only if its author is a member),
  then `Room#receive` touching the room and marking absent members unread. A writer that finds the
  write lock taken waits for the next commit (not SQLite's 1–100 ms sleeps), and WAL checkpoints run
  on a thread of their own, not in the commit that crosses 1,000 pages. The Rust port goes further:
  a single writer thread, so its writes never contend. Push notifications are queued in SQLite and
  delivered by a job every couple of seconds.
- **Sessions are a table**, and each worker keeps a resolved session for `SESSION_CACHE_TTL_MS`
  (2 s by default; 0 turns it off), so most requests authenticate without a query.
- **Literal `LIMIT`s.** SQLite 3.53 ran the room page's query four times slower with a bound
  `LIMIT ?` (189 µs against 48 µs); constant limits are written into the SQL.

### Reproducing

These figures compare two implementations on one machine. The reference README's table was measured on
another (an AMD Ryzen AI MAX+ 395) and cannot be read against them. Action Cable throughput and
many-client memory were not measured.

With a seed from the Rust port (`parity/bin/seed build default`) and the loadgen built
(`cd bench/loadgen && cargo build --release`):

```sh
ALL="room_show messages_page sidebar search post_message up"
bench/run      --seed SEED --loadgen LOADGEN --workers 8 --reps 3 --compress --only "$ALL"   # this app, gzip
bench/run-rust --seed SEED --loadgen LOADGEN --image campfire-rust:9872c1d --reps 3 --only "$ALL"
bench/run      --seed SEED --loadgen LOADGEN --workers 8 --reps 3 --gzip 0 --only "$ALL"     # no compression
bench/run-rust --seed SEED --loadgen LOADGEN --image campfire-rust:9872c1d --reps 3 --gzip 0 --only "$ALL"
```

`bench/run` creates a fresh SQLite file in a temporary directory, imports the seed and runs
`db/seeds/after_import.sl` (and, with `--proxy`, starts a Soli Proxy with compression on, on the same
CPUs); both scripts pin every process, record CPU per request (user and system), memory (RSS,
anonymous, PSS) and cold start, and write raw results to `bench/results/`. Set `BENCH_APP_PORT` when
the default port (5299) is taken. The results above are in `bench/results/rbuild2-20261009/`
(`soli-gzip`, `rust-gzip`, `soli-identity`, `rust-identity`, and `*-nocache-*` without the response
caches: `SOLI_RESPONSE_CACHE_MB=0 bench/run …`, `CAMPFIRE_RESPONSE_CACHE_MB=0 bench/run-rust …`); the earlier SoliDB runs are in
`bench/results/rbuild2-20261007/` and `bench/results/rbuild2-20261005/`.

## Known differences

- **Storage.** SQLite, but not the reference's schema: rows keyed by integer strings (the frontend
  `parseInt`s ids), times in epoch milliseconds, a message's rich text and rendered HTML on its row,
  attachments as a JSON column. Files are kept like Active Storage's disk service, under
  `storage/blobs`, described by a `blobs` table.
- **Passwords.** Soli verifies Argon2, not bcrypt; `bin/import-seed` gives imported users an Argon2
  digest of the seed's password.
- **Search.** FTS5 with the porter tokenizer, as in the reference, kept by triggers on `messages`.
  Each word of the query is quoted, so `AND`, `OR`, `NEAR` or `*` typed in a search are words, not
  operators.
- **Action Cable.** The server sends no pings (a Soli app has no in-process timer); the client is
  patched so that silence on an open socket is not taken for a dead one (OVERRIDES.md). Soli answers
  the `actioncable-v1-json` subprotocol since 2.18.7; before it, Chromium closed
  the socket at the handshake and no live update arrived.
- **Load generator.** `bench/loadgen` adds an `Origin` header to same-origin requests, which Soli's
  forgery protection checks in place of `Sec-Fetch-Site`.
- **The sidebar outside a frame.** `/users/me/sidebar` always answers with the frame alone. Rails
  renders the application layout around it unless the request carries `Turbo-Frame`, as a browser's
  does.
- **Web Push** needs `VAPID_PUBLIC_KEY` and `VAPID_PRIVATE_KEY`; without them the queue is emptied.

## Third-party code

The frontend in `reference/`, the gem assets in `vendor/` and `bench/loadgen` are MIT-licensed by their
authors; their license files sit beside them.
