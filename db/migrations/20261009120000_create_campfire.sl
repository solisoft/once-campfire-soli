# The reference's schema (db/schema.rb at 2025_12_12_154340) in SQLite, with the app's own
# field names: rows are keyed by "_key" (an integer string, see Ids), times are epoch
# milliseconds, and a message carries its rich text body, its attachment (JSON) and its
# cached HTML. A message's big columns come last: a page reads keys, times and html_key
# without going through the overflow pages its HTML takes. The indexes are the Rust port's (crates/db/src/schema.sql), which adds
# (room_id, created_at) and (room_id, updated_at) on messages to the reference's.
#
# Tables the reference keeps in Redis or Active Storage tables are here too: blobs (the files
# are under storage/blobs), Action Cable's connection and presence bookkeeping, rate limit
# counters and the push queue.

def up(db: Any)
  db.execute("""
    CREATE TABLE accounts (
      _key TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, join_code TEXT NOT NULL, custom_styles TEXT,
      settings TEXT, logo TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)
  """)
  db.execute("""
    CREATE TABLE users (
      _key TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, email_address TEXT, password_digest TEXT,
      role TEXT NOT NULL DEFAULT 'member', status TEXT NOT NULL DEFAULT 'active', bio TEXT, bot_token TEXT,
      avatar TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)
  """)
  db.execute("CREATE UNIQUE INDEX index_users_on_email_address ON users (email_address)")
  db.execute("CREATE UNIQUE INDEX index_users_on_bot_token ON users (bot_token)")
  db.execute("""
    CREATE TABLE rooms (
      _key TEXT PRIMARY KEY NOT NULL, name TEXT, type TEXT NOT NULL, creator_id TEXT NOT NULL,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)
  """)
  db.execute("""
    CREATE TABLE memberships (
      _key TEXT PRIMARY KEY NOT NULL, room_id TEXT NOT NULL, user_id TEXT NOT NULL,
      involvement TEXT DEFAULT 'mentions', unread_at INTEGER, connected_at INTEGER,
      connections INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)
  """)
  db.execute("CREATE UNIQUE INDEX index_memberships_on_room_id_and_user_id ON memberships (room_id, user_id)")
  db.execute("CREATE INDEX index_memberships_on_room_id_and_created_at ON memberships (room_id, created_at)")
  db.execute("CREATE INDEX index_memberships_on_user_id ON memberships (user_id)")
  db.execute("""
    CREATE TABLE messages (
      _key TEXT PRIMARY KEY NOT NULL, room_id TEXT NOT NULL, creator_id TEXT NOT NULL,
      client_message_id TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, html_key TEXT,
      attachment TEXT, plain_text TEXT, body TEXT, html TEXT)
  """)
  db.execute("CREATE INDEX index_messages_on_creator_id ON messages (creator_id)")
  db.execute("CREATE INDEX index_messages_on_room_id_and_created_at ON messages (room_id, created_at)")
  db.execute("CREATE INDEX index_messages_on_room_id_and_updated_at ON messages (room_id, updated_at)")
  # Message::Searchable: the plain text under the message's key, kept by triggers.
  db.execute("CREATE VIRTUAL TABLE message_search_index USING fts5 (body, tokenize=porter)")
  db.execute("""
    CREATE TRIGGER messages_search_insert AFTER INSERT ON messages BEGIN
      INSERT INTO message_search_index (rowid, body) VALUES (CAST(new._key AS INTEGER), coalesce(new.plain_text, ''));
    END
  """)
  db.execute("""
    CREATE TRIGGER messages_search_update AFTER UPDATE OF plain_text ON messages BEGIN
      UPDATE message_search_index SET body = coalesce(new.plain_text, '') WHERE rowid = CAST(new._key AS INTEGER);
    END
  """)
  db.execute("""
    CREATE TRIGGER messages_search_delete AFTER DELETE ON messages BEGIN
      DELETE FROM message_search_index WHERE rowid = CAST(old._key AS INTEGER);
    END
  """)
  db.execute("""
    CREATE TABLE boosts (
      _key TEXT PRIMARY KEY NOT NULL, message_id TEXT NOT NULL, booster_id TEXT NOT NULL, content TEXT NOT NULL,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)
  """)
  db.execute("CREATE INDEX index_boosts_on_booster_id ON boosts (booster_id)")
  db.execute("CREATE INDEX index_boosts_on_message_id ON boosts (message_id)")
  db.execute("""
    CREATE TABLE sessions (
      token TEXT PRIMARY KEY NOT NULL, user_id TEXT NOT NULL, user_agent TEXT, ip_address TEXT,
      last_active_at INTEGER NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)
  """)
  db.execute("CREATE INDEX index_sessions_on_user_id ON sessions (user_id)")
  db.execute("""
    CREATE TABLE searches (
      _key TEXT PRIMARY KEY NOT NULL, user_id TEXT NOT NULL, query TEXT NOT NULL,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)
  """)
  db.execute("CREATE INDEX index_searches_on_user_id ON searches (user_id)")
  db.execute("""
    CREATE TABLE bans (
      _key TEXT PRIMARY KEY NOT NULL, user_id TEXT NOT NULL, ip_address TEXT NOT NULL,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)
  """)
  db.execute("CREATE INDEX index_bans_on_ip_address ON bans (ip_address)")
  db.execute("CREATE INDEX index_bans_on_user_id ON bans (user_id)")
  db.execute("""
    CREATE TABLE push_subscriptions (
      _key TEXT PRIMARY KEY NOT NULL, user_id TEXT NOT NULL, endpoint TEXT, p256dh_key TEXT, auth_key TEXT,
      user_agent TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)
  """)
  db.execute("CREATE INDEX index_push_subscriptions_on_endpoint_and_keys ON push_subscriptions (endpoint, p256dh_key, auth_key)")
  db.execute("CREATE INDEX index_push_subscriptions_on_user_id ON push_subscriptions (user_id)")
  db.execute("""
    CREATE TABLE webhooks (
      _key TEXT PRIMARY KEY NOT NULL, user_id TEXT NOT NULL, url TEXT,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)
  """)
  db.execute("CREATE INDEX index_webhooks_on_user_id ON webhooks (user_id)")
  db.execute("""
    CREATE TABLE blobs (
      _key TEXT PRIMARY KEY NOT NULL, filename TEXT NOT NULL, content_type TEXT, byte_size INTEGER NOT NULL,
      created_at INTEGER NOT NULL)
  """)
  db.execute("""
    CREATE TABLE cable_connections (
      connection_id TEXT PRIMARY KEY NOT NULL, user_id TEXT NOT NULL, created_at INTEGER NOT NULL)
  """)
  db.execute("CREATE INDEX index_cable_connections_on_user_id ON cable_connections (user_id)")
  db.execute("""
    CREATE TABLE cable_presences (
      connection_id TEXT NOT NULL, membership_id TEXT NOT NULL, PRIMARY KEY (connection_id, membership_id))
    WITHOUT ROWID
  """)
  db.execute("CREATE TABLE rate_limits (name TEXT PRIMARY KEY NOT NULL, count INTEGER NOT NULL, expires_at INTEGER NOT NULL) WITHOUT ROWID")
  db.execute("CREATE TABLE push_queue (id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT NOT NULL)")
end

def down(db: Any)
  for name in ["push_queue", "rate_limits", "cable_presences", "cable_connections", "blobs", "webhooks",
               "push_subscriptions", "bans", "searches", "sessions", "boosts", "message_search_index", "messages",
               "memberships", "rooms", "users", "accounts"]
    db.execute("DROP TABLE IF EXISTS " + name)
  end
end
