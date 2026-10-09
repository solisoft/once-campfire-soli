class Boost < Model
  static def find_hash(key)
    return nil if key.nil?

    Db.find_row("boosts", key)
  end

  static def create_boost(message, booster_key, content)
    now = Clock.now
    created = Ids.create("boosts", {"message_id": message["_key"], "booster_id": booster_key, "content": content,
                                    "created_at": now, "updated_at": now})
    Message.touch(message["_key"])
    created
  end

  static def destroy_boost(boost)
    Db.delete_row("boosts", boost["_key"])
    Message.touch(boost["message_id"])
  end

  # message.boosts.ordered, each with its booster.
  static def for_messages(message_keys)
    return {} if message_keys.length == 0

    rows = Db.rows("SELECT json_object(" + Db.fields("boosts", "b") + ", 'booster', " + Db.json("users", "u") + ") AS j " +
                   "FROM boosts b LEFT JOIN users u ON u._key = b.booster_id WHERE b.message_id IN (" + Db.marks(message_keys) + ") " +
                   "ORDER BY b.created_at, b._key", message_keys)
    grouped_boosts = {}
    for b in rows
      grouped_boosts[b["message_id"]] = (grouped_boosts[b["message_id"]] ?? []) + [b]
    end
    grouped_boosts
  end
end
