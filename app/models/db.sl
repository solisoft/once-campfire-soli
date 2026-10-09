# SQLite, through Model.find_by_sql: it runs any one statement, its binds positional (?).
#
# Rows come back as plain hashes. A query selects one JSON object per row, named j (Db.json
# writes the json_object of a table's row), and Db.rows has SQLite join them into one JSON
# array, parsed once: no model instances, NULLs and numbers as stored, JSON columns
# (attachment, avatar, logo, settings) as hashes.
#
# A failed statement raises. Binds: a hash or an array is stored as JSON text, and nil is
# written as a NULL literal (find_by_sql binds nil as "", soli 2.18.4).
class Db < Model
  static COLUMNS: Hash = {
    "accounts": ["_key", "name", "join_code", "custom_styles", "settings", "logo", "created_at", "updated_at"],
    "users": ["_key", "name", "email_address", "password_digest", "role", "status", "bio", "bot_token", "avatar",
              "created_at", "updated_at"],
    "rooms": ["_key", "name", "type", "creator_id", "created_at", "updated_at"],
    "memberships": ["_key", "room_id", "user_id", "involvement", "unread_at", "connected_at", "connections",
                    "created_at", "updated_at"],
    "messages": ["_key", "room_id", "creator_id", "client_message_id", "body", "attachment", "plain_text", "html",
                 "html_key", "created_at", "updated_at"],
    "boosts": ["_key", "message_id", "booster_id", "content", "created_at", "updated_at"],
    "sessions": ["token", "user_id", "user_agent", "ip_address", "last_active_at", "created_at", "updated_at"],
    "searches": ["_key", "user_id", "query", "created_at", "updated_at"],
    "bans": ["_key", "user_id", "ip_address", "created_at", "updated_at"],
    "push_subscriptions": ["_key", "user_id", "endpoint", "p256dh_key", "auth_key", "user_agent", "created_at",
                           "updated_at"],
    "webhooks": ["_key", "user_id", "url", "created_at", "updated_at"],
    "blobs": ["_key", "filename", "content_type", "byte_size", "created_at"]
  }
  static JSON_COLUMNS: Array = ["settings", "logo", "avatar", "attachment"]
  static FIELDS: Hash = {}

  # "'_key', m._key, 'name', m.name, …": a table's row under an alias, as json_object pairs
  # (to add keys of one's own).
  static def fields(table, alias_name)
    name = table + " " + alias_name
    found = Db.FIELDS[name]
    return found unless found.nil?

    pairs = Db.COLUMNS[table].map { |c|
      value = alias_name + "." + c
      "'" + c + "', " + (Db.JSON_COLUMNS.include?(c) ? "json(" + value + ")" : value)
    }
    Db.FIELDS[name] = pairs.join(", ")
    Db.FIELDS[name]
  end

  static def json(table, alias_name)
    "json_object(" + Db.fields(table, alias_name) + ")"
  end

  # The statement's rows as model instances (RETURNING, single values).
  static def exec(sql, binds = [])
    plain = true
    for b in binds
      if b.nil? || b.is_a?("hash") || b.is_a?("array")
        plain = false
        break
      end
    end
    return Db.find_by_sql(sql, binds) if plain

    parts = sql.split("?")
    text = parts[0]
    values = []
    i = 0
    while i < binds.length
      b = binds[i]
      if b.nil?
        text += "NULL"
      else
        text += "?"
        values.push(b.is_a?("hash") || b.is_a?("array") ? json_stringify(b) : b)
      end
      text += i + 1 < parts.length ? parts[i + 1] : ""
      i += 1
    end
    Db.find_by_sql(text, values)
  end

  # Rows as hashes: sql selects one JSON object per row, as j.
  static def rows(sql, binds = [])
    found = Db.exec("SELECT '[' || group_concat(j, ',') || ']' AS j FROM (" + sql + ")", binds)
    text = found[0]["j"]
    text.nil? ? [] : json_parse(text)
  end

  static def row(sql, binds = [])
    found = Db.rows(sql, binds)
    found.length > 0 ? found[0] : nil
  end

  # The first row's column v.
  static def value(sql, binds = [])
    found = Db.exec(sql, binds)
    found.length > 0 ? found[0]["v"] : nil
  end

  static def find_row(table, key)
    return nil if key.nil?

    Db.row("SELECT " + Db.json(table, "t") + " AS j FROM " + table + " t WHERE t._key = ?", [str(key)])
  end

  static def insert(table, attrs)
    columns = attrs.keys
    Db.exec("INSERT INTO " + table + " (" + columns.join(", ") + ") VALUES (" + columns.map { |c| "?" }.join(", ") + ")",
            columns.map { |c| attrs[c] })
    attrs
  end

  static def update_row(table, key, fields)
    columns = fields.keys
    binds = columns.map { |c| fields[c] }
    binds.push(str(key))
    Db.exec("UPDATE " + table + " SET " + columns.map { |c| c + " = ?" }.join(", ") + " WHERE _key = ?", binds)
  end

  static def delete_row(table, key)
    Db.exec("DELETE FROM " + table + " WHERE _key = ?", [str(key)])
  end

  # "?, ?, ?" for an IN list.
  static def marks(values)
    values.map { |v| "?" }.join(", ")
  end
end
