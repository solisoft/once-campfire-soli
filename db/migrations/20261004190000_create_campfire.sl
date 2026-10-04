# The reference's schema (db/schema.rb at 2025_12_12_154340) as SoliDB collections.
# Rows reference each other by _key; times are epoch milliseconds.

def up(db: Any)
  for name in ["accounts", "users", "rooms", "memberships", "messages", "boosts", "sessions",
               "searches", "bans", "push_subscriptions", "webhooks"]
    db.create_collection(name)
  end
  db.create_collection("attachments", "blob")

  db.create_index("users", "idx_users_email", ["email_address"], {"unique": true})
  db.create_index("users", "idx_users_bot_token", ["bot_token"], {})
  db.create_index("users", "idx_users_status", ["status"], {})

  db.create_index("memberships", "idx_memberships_room_user", ["room_id", "user_id"], {"unique": true})
  db.create_index("memberships", "idx_memberships_room", ["room_id"], {})
  db.create_index("memberships", "idx_memberships_user", ["user_id"], {})

  db.create_index("rooms", "idx_rooms_type", ["type"], {})

  db.create_index("messages", "idx_messages_room", ["room_id"], {})
  db.create_index("messages", "idx_messages_room_created", ["room_id", "created_at"], {"type": "persistent"})
  db.create_index("messages", "idx_messages_creator", ["creator_id"], {})
  db.create_index("messages", "idx_messages_search", ["search_text"], {"type": "fulltext"})

  db.create_index("boosts", "idx_boosts_message", ["message_id"], {})
  db.create_index("boosts", "idx_boosts_booster", ["booster_id"], {})

  db.create_index("sessions", "idx_sessions_token", ["token"], {"unique": true})
  db.create_index("sessions", "idx_sessions_user", ["user_id"], {})

  db.create_index("searches", "idx_searches_user", ["user_id"], {})
  db.create_index("bans", "idx_bans_ip", ["ip_address"], {})
  db.create_index("bans", "idx_bans_user", ["user_id"], {})
  db.create_index("push_subscriptions", "idx_push_subscriptions_user", ["user_id"], {})
  db.create_index("webhooks", "idx_webhooks_user", ["user_id"], {})
end

def down(db: Any)
  for name in ["accounts", "users", "rooms", "memberships", "messages", "boosts", "sessions",
               "searches", "bans", "push_subscriptions", "webhooks", "attachments"]
    db.drop_collection(name)
  end
end
