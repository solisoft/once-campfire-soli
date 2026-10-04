class Boost < Model
  static def find_hash(key)
    return nil if key.nil?

    k = str(key)
    rows = @sdbql{ FOR b IN boosts FILTER b._key == #{k} LIMIT 1 RETURN b }
    Db.first(rows)
  end

  static def create_boost(message, booster_key, content)
    now = Clock.now
    created = Ids.create(Boost, {"message_id": message["_key"], "booster_id": booster_key, "content": content,
                            "created_at": now, "updated_at": now})
    Message.touch(message["_key"])
    Boost.find_hash(created._key)
  end

  static def destroy_boost(boost)
    k = boost["_key"]
    @sdbql{ FOR b IN boosts FILTER b._key == #{k} REMOVE b IN boosts }
    Message.touch(boost["message_id"])
  end

  # message.boosts.ordered, each with its booster.
  static def for_messages(message_keys)
    return {} if message_keys.length == 0

    rows = @sdbql{
      FOR b IN boosts FILTER b.message_id IN #{message_keys}
        SORT b.created_at, b._key
        LET booster = FIRST(FOR u IN users FILTER u._key == b.booster_id RETURN u)
        RETURN MERGE(b, {booster: booster})
    }
    grouped_boosts = {}
    for b in (Db.array(rows))
      grouped_boosts[b["message_id"]] = (grouped_boosts[b["message_id"]] ?? []) + [b]
    end
    grouped_boosts
  end
end
