class Message < Model
  static PAGE_SIZE: Int = 40

  static def find_hash(key)
    return nil if key.nil?

    Db.find_row("messages", key)
  end

  static def find_in_room(room_key, key)
    return nil if key.nil?

    Db.row("SELECT " + Db.json("messages", "m") + " AS j FROM messages m WHERE m._key = ? AND m.room_id = ?",
           [str(key), str(room_key)])
  end

  # Messages by key, in the order given.
  static def find_many_ordered(keys)
    return [] if keys.length == 0

    found = {}
    for m in Db.rows("SELECT " + Db.json("messages", "m") + " AS j FROM messages m WHERE m._key IN (" + Db.marks(keys) + ")", keys)
      found[m["_key"]] = m
    end
    keys.map { |k| found[k] }.filter { |m| !m.nil? }
  end

  # Current.user.reachable_messages.find
  static def find_reachable(user_key, key)
    return nil if key.nil?

    Db.row("SELECT " + Db.json("messages", "m") + " AS j FROM messages m " +
           "JOIN memberships s ON s.room_id = m.room_id AND s.user_id = ? WHERE m._key = ?", [user_key, str(key)])
  end

  # room.messages.create_with_attachment! with its after_create_commit (Room#receive) and the
  # presentation it will be shown with: it checks that the creator is a
  # member, puts the message in with its HTML, touches the room, marks unread the members who
  # are neither its author, invisible nor connected, and returns the room and its members.
  # nil when the creator is not a member (nothing is written).
  #
  # The HTML shows the room's name, needed before the statement runs: each worker keeps the
  # name it last rendered for the room, and when the room the statement returns says another
  # (a rename, or a member's name in a direct room), the message is rendered again.
  #
  # Only the members who turn unread are written: Room#unread_memberships rewrites unread_at on
  # every message, but nothing reads that time beyond whether it is set.
  static def post(room_key, creator, body_html, attachment, client_message_id, base_url)
    rk = str(room_key)
    ck = creator["_key"]
    cache_name = "message_room_name:" + rk
    cached_name = PageCache.get(cache_name)
    room_name = cached_name
    if room_name.nil?
      found = Room.with_member_names(rk)
      return nil if found.nil?

      room_name = Room.message_room_name(found["room"], found["names"])
    end

    now = Clock.now
    analyzed = attachment.nil? ? RichText.analyze(body_html) : {"plain": "", "mentions": []}
    plain = analyzed["plain"]
    plain = attachment["filename"] if plain.blank? && !attachment.nil?
    doc = {
      "room_id": rk, "creator_id": ck,
      "client_message_id": client_message_id.blank? ? UUID.v4() : client_message_id,
      "body": attachment.nil? ? body_html : nil, "attachment": attachment, "plain_text": plain ?? "",
      "created_at": now, "updated_at": now
    }
    cutoff = now - Membership.CONNECTION_TTL_MS
    posted = nil
    for attempt in 0..5
      doc["_key"] = Ids.generate
      doc["html"] = MessagePresenter.render_new(doc, creator, room_name, base_url)
      doc["html_key"] = MessagePresenter.cache_key(doc)
      try
        posted = Message.insert_posted(doc, rk, ck, now, cutoff)
        break
      catch error
        # Another write took the key in the same microsecond: nothing was written.
        throw error unless str(error).contains("UNIQUE constraint failed: messages._key") && attempt < 4
      end
    end
    return nil if posted.nil?

    room = posted["room"]
    members = posted["members"]
    fresh_name = Room.message_room_name(room, members.map { |m| m["name"] })
    if fresh_name != room_name
      doc["html"] = MessagePresenter.render_new(doc, creator, fresh_name, base_url)
      Message.save_html(doc["_key"], doc["html"], doc["html_key"])
    end
    PageCache.set_bounded(cache_name, fresh_name, "message_room_names", 64) if fresh_name != cached_name
    Message.queue_push(room, doc, ck, members, analyzed["mentions"], cutoff)
    {"message": doc, "room": room, "members": members.map { |m| m["user_id"] }}
  end

  # The writes of Message.post, as the reference makes them: the message, only when its creator
  # is a member (one INSERT … SELECT), then Room#receive (after_create_commit), which touches the
  # room and marks the absent members unread. Each statement commits on its own, so SQLite's write
  # lock is never held while Soli code runs between statements. {room, members}, or nil when the
  # creator is not a member.
  static def insert_posted(doc, rk, ck, now, cutoff)
    columns = doc.keys
    inserted = Db.exec("INSERT INTO messages (" + columns.join(", ") + ") SELECT " + Db.marks(columns) +
                       " WHERE EXISTS (SELECT 1 FROM memberships WHERE room_id = ? AND user_id = ?) RETURNING _key",
                       columns.map { |c| doc[c] } + [rk, ck])
    return nil if inserted.length == 0

    Db.exec("UPDATE rooms SET updated_at = ? WHERE _key = ?", [now, rk])
    Db.exec("UPDATE memberships SET unread_at = ?, updated_at = ? WHERE room_id = ? AND user_id != ? " +
            "AND involvement IS NOT 'invisible' AND unread_at IS NULL AND (connected_at IS NULL OR connected_at < ?)",
            [now, now, rk, ck, cutoff])
    members = Db.rows("SELECT json_object('user_id', o.user_id, 'name', u.name, 'involvement', o.involvement, " +
                      "'connected_at', o.connected_at) AS j FROM memberships o JOIN users u ON u._key = o.user_id " +
                      "WHERE o.room_id = ? ORDER BY CAST(u._key AS INTEGER), u._key", [rk])
    {"room": Db.find_row("rooms", rk), "members": members}
  end

  # Room::PushMessageJob's recipients: the members who turned unread (by the same test as the
  # statement's, unread_at aside) and follow the room or were mentioned. Those without a push
  # subscription are left out when the queue is delivered. Nothing is queued without VAPID keys,
  # since nothing could be delivered.
  static def queue_push(room, message, author_key, members, mentioned, cutoff)
    return nil unless WebPush.configured?

    push_to = []
    for m in members
      unread = m["user_id"] != author_key && m["involvement"] != "invisible" && (m["connected_at"].nil? || m["connected_at"] < cutoff)
      involved = m["involvement"] == "everything" || (m["involvement"] == "mentions" && mentioned.include?(m["user_id"]))
      push_to.push(m["user_id"]) if unread && involved
    end
    PushQueue.enqueue({"room_id": room["_key"], "message_id": message["_key"], "user_ids": push_to}) if push_to.length > 0
  end

  static def update_body(message, body_html)
    now = Clock.now
    plain = RichText.plain_text(body_html)
    Db.update_row("messages", message["_key"], {"body": body_html, "plain_text": plain, "updated_at": now})
    Room.touch(message["room_id"], now)
    Message.find_hash(message["_key"])
  end

  # belongs_to :message, touch: true on boosts
  static def touch(key)
    Db.exec("UPDATE messages SET updated_at = ? WHERE _key = ?", [Clock.now, str(key)])
  end

  static def destroy_message(message)
    k = message["_key"]
    Db.exec("DELETE FROM boosts WHERE message_id = ?", [k])
    Attachments.delete_for(message["attachment"])
    Db.delete_row("messages", k)
    Room.touch(message["room_id"])
  end

  # user.messages (User::Bannable#remove_banned_content)
  static def created_by(user_key)
    Db.rows("SELECT " + Db.json("messages", "m") + " AS j FROM messages m WHERE m.creator_id = ? " +
            "ORDER BY m.created_at, m._key", [user_key])
  end

  static def destroy_all_in_room(room_key)
    rk = room_key
    rows = Db.rows("SELECT attachment AS j FROM messages WHERE room_id = ? AND attachment IS NOT NULL", [rk])
    for a in rows
      Attachments.delete_for(a)
    end
    Db.exec("DELETE FROM boosts WHERE message_id IN (SELECT _key FROM messages WHERE room_id = ?)", [rk])
    Db.exec("DELETE FROM messages WHERE room_id = ?", [rk])
  end

  static def save_html(key, html, html_key)
    Db.exec("UPDATE messages SET html = ?, html_key = ? WHERE _key = ?", [html, html_key, str(key)])
  end

  # --- Message::Pagination ----------------------------------------------------------------

  static def last_page(room_key, size = 40)
    Db.rows("SELECT " + Db.json("messages", "m") + " AS j FROM messages m WHERE m.room_id = ? " +
            "ORDER BY m.created_at DESC, m._key DESC LIMIT " + str(int(size)), [room_key]).reverse
  end

  static def page_before(room_key, message, size = 40)
    Db.rows("SELECT " + Db.json("messages", "m") + " AS j FROM messages m WHERE m.room_id = ? AND m.created_at < ? " +
            "ORDER BY m.created_at DESC, m._key DESC LIMIT " + str(int(size)), [room_key, message["created_at"]]).reverse
  end

  static def page_after(room_key, message, size = 40)
    Db.rows("SELECT " + Db.json("messages", "m") + " AS j FROM messages m WHERE m.room_id = ? AND m.created_at > ? " +
            "ORDER BY m.created_at, m._key LIMIT " + str(int(size)), [room_key, message["created_at"]])
  end

  static def page_around(room_key, message)
    Message.page_before(room_key, message) + [message] + Message.page_after(room_key, message)
  end

  static def page_created_since(room_key, since)
    Db.rows("SELECT " + Db.json("messages", "m") + " AS j FROM messages m WHERE m.room_id = ? AND m.created_at > ? " +
            "ORDER BY m.created_at, m._key LIMIT 40", [room_key, since])
  end

  static def page_updated_since(room_key, since, excluded_keys)
    binds = [room_key, since] + excluded_keys
    Db.rows("SELECT " + Db.json("messages", "m") + " AS j FROM messages m WHERE m.room_id = ? AND m.updated_at > ? " +
            "AND m._key NOT IN (" + Db.marks(excluded_keys) + ") ORDER BY m.created_at DESC, m._key DESC LIMIT 40",
            binds).reverse
  end

  static def count_in_room(room_key)
    Db.value("SELECT count(*) AS v FROM messages WHERE room_id = ?", [room_key])
  end

  static def paged?(room_key)
    Db.value("SELECT count(*) AS v FROM (SELECT 1 FROM messages WHERE room_id = ? LIMIT ?)",
             [room_key, Message.PAGE_SIZE + 1]) > Message.PAGE_SIZE
  end

  static def exists_before?(room_key, message)
    Db.value("SELECT EXISTS (SELECT 1 FROM messages WHERE room_id = ? AND created_at < ?) AS v",
             [room_key, message["created_at"]]) == 1
  end

  static def exists_after?(room_key, message)
    Db.value("SELECT EXISTS (SELECT 1 FROM messages WHERE room_id = ? AND created_at > ?) AS v",
             [room_key, message["created_at"]]) == 1
  end

  # --- Message::Searchable ----------------------------------------------------------------

  # The FTS5 query for what was typed: its words, each quoted (so none is read as an
  # operator), all of them required.
  static def search_query(query)
    Stemmer.query_terms(query).map { |t| "\"" + t + "\"" }.join(" ")
  end

  # --- presentation ---------------------------------------------------------------------

  static def content_type(message)
    return "attachment" unless message["attachment"].nil?
    return "sound" unless Sounds.from_body(message["plain_text"]).nil?

    "text"
  end
end
