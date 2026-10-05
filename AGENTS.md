# once-campfire-soli

Campfire (the Rails app pinned in `reference/`) ported to Soli, on SoliDB and SoliKV. The
frontend is the reference's, unchanged except for `overrides/` and the edits `bin/build-assets`
applies. Behaviour and HTML follow the reference; storage does not (SoliDB documents, not SQLite
tables), so this is not a drop-in for an existing install.

Load the `soli-lang` and `solidb` skills before writing Soli or SDBQL.

## Layout

| Path | What |
|---|---|
| `app/models/*.sl` | One class per collection. Static methods; rows are plain hashes (`user["name"]`). Hot paths use `@sdbql{}`. |
| `app/services/*.sl` | Everything else (sessions are in SoliKV, see `app/models/session.sl` and SessionCache): Authentication, Cable (Action Cable), RichText, MessagePresenter, RoomPage/MessagePage/SearchPage/Sidebar (the benchmarked pages), Present (view decoration), PageCache, Signer, Ids, Attachments, PushQueue/MessagePusher/WebPush, Opengraph, Sounds… |
| `app/controllers/` | `x/y_controller.sl` → `class XYController`. All inherit ApplicationController. |
| `app/helpers/*.sl` | Functions for views (`image_tag`, `avatar_tag`, `button_to`, `translation_button`, …). |
| `app/views/**/*.html.slv` | Ported ERB. |
| `config/routes.sl` | Every route of the reference's routes.rb, already declared. |
| `bin/build-assets` | Propshaft port: `public/assets` + `app/helpers/asset_manifest.sl` + `app/services/asset_manifest.sl`. Run after a clone. |
| `bin/import-seed`, `db/seeds/after_import.sl` | Load a reference parity seed into SoliDB. |
| `bench/` | `bench/run` (the README's five workloads), `bench/loadgen`, `bench/cable_probe.py`. |

## Conventions

- **Keys are integer strings.** The frontend `parseInt`s user and room ids. Create rows with
  `Ids.create(Model, attrs)` (or `"_key": Ids.generate` in SDBQL inserts), never a bare `Model.create`.
- **Times are epoch milliseconds** (`Clock.now`), fields `created_at` / `updated_at`.
- **Rows are hashes.** Models expose `find_hash`, query helpers, and write helpers. Wrap every
  `@sdbql{}` result with `Db.array(rows)` / `Db.first(rows)`: a failed query returns an error
  *string*, and those helpers log it.
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

## Soli and SoliDB traps met here

- `if xs.filter { |x| … }.length > 0` does not parse (the `{` is read as the if's body). Assign first.
- Inside `@sdbql{}`, Soli values are `#{bare_name}` only; a bare `t` is an SDBQL variable. No `#`
  comments inside the block. `LIMIT var` on a collection scan returns nothing: `SLICE(…, 0, var)`.
- `FULLTEXT` ORs terms; `SearchPage` ANDs them. SoliDB keeps a 60 s query cache.
- No `^`/`&` operators (see `Crc32`), no `rindex`, `index_of` is not a method in controllers.
- `--dev` hot reload does not give a controller *added* while running its inherited hooks: restart.
- Never `pkill -f <pattern>` from a shell whose own command line contains the pattern; use
  `fuser -k PORT/tcp`.
- SoliKV listens on 127.0.0.1 only: `SOLIKV_RESP_HOST=127.0.0.1`.

## Running

```sh
bin/build-assets
soli db:migrate up
bin/import-seed PATH/TO/parity/.seed/default && soli db:seed . db/seeds/after_import.sl
soli serve . --dev --port 5197          # dev; production: soli serve . --port 5198 --workers 8
```

Sign in as `david@37signals.com` / `secret123456` (the seed's users all share that password).
Behind Soli Proxy it is https://campfire.solisoft.test (`soli-proxy restart campfire.solisoft.test`).

The reference Rails app on the same seed (for comparing HTML) runs from the Rust port's
checkout: `parity/bin/reference up --seed default --port 3100`.
