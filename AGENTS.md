# once-campfire-soli

Campfire (the Rails app pinned in `reference/`) ported to Soli, on one SQLite file (attachments
are files beside it). The frontend is the reference's, unchanged except for `overrides/` and the
edits `bin/build-assets` applies. Behaviour and HTML follow the reference; the schema does not
(the app's own tables: string keys, epoch-millisecond times, a message's body, attachment and HTML
on its row), so this is not a drop-in for an existing install.

Load the `soli-lang` skill before writing Soli.

## Layout

| Path | What |
|---|---|
| `app/models/*.sl` | One class per table. Static methods; rows are plain hashes (`user["name"]`). SQL goes through `Db` (`app/models/db.sl`). |
| `app/services/*.sl` | Everything else (sessions are a table, see `app/models/session.sl` and SessionCache): Authentication, Cable (Action Cable), RichText, MessagePresenter, RoomPage/MessagePage/SearchPage/Sidebar (the benchmarked pages), Present (view decoration), PageCache, Signer, Ids, Attachments, PushQueue/MessagePusher/WebPush, Opengraph, Sounds… |
| `app/controllers/` | `x/y_controller.sl` → `class XYController`. All inherit ApplicationController. |
| `app/helpers/*.sl` | Functions for views (`image_tag`, `avatar_tag`, `button_to`, `translation_button`, …). |
| `app/views/**/*.html.slv` | Ported ERB. |
| `config/routes.sl` | Every route of the reference's routes.rb, already declared. |
| `bin/build-assets` | Propshaft port: `public/assets` + `app/helpers/asset_manifest.sl` + `app/services/asset_manifest.sl`. Run after a clone. |
| `db/migrations/` | The whole schema in one migration (SQL), with the FTS5 search index and its triggers. |
| `bin/import-seed`, `db/seeds/after_import.sl` | Load a reference parity seed into the SQLite file. |
| `bench/` | `bench/run` (the README's five workloads), `bench/loadgen`, `bench/cable_probe.py`. |

## Conventions

- **Keys are integer strings** (`_key TEXT`). The frontend `parseInt`s user and room ids. Create
  rows with `Ids.create("table", attrs)` (it retries a key taken in the same microsecond), or
  `Db.insert` with a `_key` you chose. No ORM calls (`Model.create`, `Model.update`, `.find`).
- **Times are epoch milliseconds** (`Clock.now`), fields `created_at` / `updated_at`.
- **SQL goes through `Db`.** A query selects one JSON object per row as `j`: `Db.json("users", "u")`
  writes the `json_object` of a row, `Db.fields` its pairs (to add keys: rooms, members, badges).
  `Db.rows(sql, binds)` → hashes, `Db.row` → the first or nil, `Db.value` → column `v` of the first
  row, `Db.exec` → runs anything (RETURNING rows come back as instances), `Db.insert`,
  `Db.update_row`, `Db.delete_row`, `Db.find_row`, `Db.marks(list)` for `IN (?, ?)`. Binds are `?`;
  a hash or array bind is stored as JSON. A failed statement raises. `Db.transaction(fn() { … })`.
- **Views can't see models, services or helper constants**, only helper *functions* and
  `@ivars`. Decorate rows in the controller: `Present.user(u)` adds `avatar_path`, `title`,
  `administrator`, `bot`. Per-thread static data in helpers goes through `I18n.cache_table`.
- **Controllers can't see helper functions.** `render_partial("x/y", {...})` works from
  controllers and services.
- `req["current_user"]`, `req["account"]` are set by `Authentication.run` (the base hook).
  `@_current_user`, `@_current_user_key`, `@_account` read them. Public routes and bot routes are
  listed in Authentication.
- Pages: `@_render_page("x/y")` (sets `@layout`, takes the flash). Flash: `@_flash("notice", "✓")`
  before a redirect. Errors: `halt(403, "")`; 404 for missing rows the way Rails' `find` would.
- Forms: page-level forms carry `<%- csrf_hidden_field() %>`. Shared or cached fragments (message
  partials, `button_to`) carry none: Turbo sends `X-CSRF-Token` from the meta tag.
- DOM ids follow Rails' `dom_id`: messages use `client_message_id` (`message_<cmid>`), rooms use
  their STI class (`Room.dom_id(room, "list")` → `list_rooms_open_1`).
- Live updates: `Cable.broadcast_stream(stream, TurboStream.append(target, html))` for Turbo
  streams (`"rooms"`, `"user:<key>:rooms"`, `"room:<key>:messages"`), `Cable.broadcast_raw(...)`
  for JS channels, `Cable.disconnect_user(key, reconnect)` for close_remote_connections.
- Message HTML is cached on the message (`html`, `html_key`); anything that changes how a message
  renders must move its `updated_at` (`Message.touch`), like Rails' `touch: true`.

## Soli and SQLite traps met here

- `if xs.filter { |x| … }.length > 0` and `for x in xs.sort_by { … }` do not parse (the `{` is read
  as the statement's body). Assign first.
- `as`, `match`, `from` are reserved; `range` shadows a builtin. Name variables otherwise.
- `find_by_sql` binds `nil` as `""` (soli 2.18.4): `Db.exec` writes `NULL` in its place, by splitting
  the SQL on `?`. So a statement with a nil bind can't use `?N`; one with `?1`, `?2`… must pass none.
- JSON loses its subtype through a subquery: wrap a scalar subquery that returns JSON in `json(…)`,
  or it is embedded as a string. Aggregates take an `ORDER BY` (`json_group_array(x ORDER BY y)`).
- A message's big columns (`body`, `html`) come last in the table: the page queries read `_key`,
  times and `html_key` without walking the HTML's overflow pages, and join `html` only when the
  worker's cached page is stale. Keep it that way when adding columns.
- `_key` is TEXT: compare it to a rowid as `m._key = CAST(idx.rowid AS TEXT)`, or the index is
  skipped. `NULL != 'x'` is NULL: use `IS NOT` on nullable columns (`involvement`).
- Write a constant `LIMIT` into the SQL (`"LIMIT " + str(int(size))`), never `LIMIT ?`: on SQLite
  3.53 the room page query took 189 µs with a bound LIMIT and 48 µs with a literal one.
- A restored database replays its cron: Soli fires every missed slot of `_cron_jobs` (one per 2 s
  of downtime for PushDeliveryJob) back to back at boot. Empty `_cron_jobs` before measuring.
- No `^`/`&` operators (see `Crc32`), no `rindex`, `index_of` is not a method in controllers.
- `--dev` hot reload does not give a controller *added* while running its inherited hooks: restart.
- Never `pkill -f <pattern>` (or `pgrep -f` in an ssh command) from a shell whose own command line
  contains the pattern; use `fuser -k PORT/tcp`.

## Running

```sh
bin/build-assets
soli db:create && soli db:migrate up     # storage/campfire.sqlite3 (DATABASE_URL)
bin/import-seed PATH/TO/parity/.seed/default && soli db:seed . db/seeds/after_import.sl
soli serve . --dev --port 5197          # dev; production: soli serve . --port 5198 --workers 8
```

Sign in as `david@37signals.com` / `secret123456` (the seed's users all share that password).
Behind Soli Proxy it is https://campfire.solisoft.test (`soli-proxy restart campfire.solisoft.test`).

The reference Rails app on the same seed (for comparing HTML) runs from the Rust port's
checkout: `parity/bin/reference up --seed default --port 3100`.
