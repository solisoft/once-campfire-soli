class Message < Model
  static PAGE_SIZE: Int = 40

  static def find_hash(key)
    return nil if key.nil?

    k = str(key)
    rows = @sdbql{ FOR m IN messages FILTER m._key == #{k} LIMIT 1 RETURN m }
    Db.first(rows)
  end

  static def find_in_room(room_key, key)
    return nil if key.nil?

    k = str(key)
    rk = room_key
    rows = @sdbql{ FOR m IN messages FILTER m._key == #{k} AND m.room_id == #{rk} LIMIT 1 RETURN m }
    Db.first(rows)
  end

  # Messages by key, in the order given.
  static def find_many_ordered(keys)
    return [] if keys.length == 0

    rows = @sdbql{ FOR k IN #{keys} FOR m IN messages FILTER m._key == k RETURN m }
    Db.array(rows)
  end

  # Current.user.reachable_messages.find
  static def find_reachable(user_key, key)
    return nil if key.nil?

    k = str(key)
    uk = user_key
    rows = @sdbql{
      FOR m IN messages FILTER m._key == #{k}
        LET member = LENGTH(FOR s IN memberships FILTER s.room_id == m.room_id AND s.user_id == #{uk} LIMIT 1 RETURN 1)
        FILTER member > 0
        LIMIT 1
        RETURN m
    }
    Db.first(rows)
  end

  # room.messages.create_with_attachment! with its after_create_commit (Room#receive) and the
  # presentation it will be shown with, in one statement: the message goes in with its HTML,
  # the room is touched, and members who aren't watching become unread.
  #
  # members are the room's memberships as Membership.with_room_and_members read them. Only the
  # ones that turn unread are written: Room#unread_memberships rewrites unread_at on every
  # message, but nothing reads that time beyond whether it is set.
  static def create_message(room, creator, body_html, attachment, client_message_id, base_url, members)
    now = Clock.now
    plain = attachment.nil? ? RichText.plain_text(body_html) : ""
    plain = attachment["filename"] if plain.blank? && !attachment.nil?
    doc = {
      "room_id": room["_key"], "creator_id": creator["_key"],
      "client_message_id": client_message_id.blank? ? UUID.v4() : client_message_id,
      "body": attachment.nil? ? body_html : nil, "plain_text": plain ?? "",
      "search_text": Stemmer.index_text(plain ?? ""), "attachment": attachment,
      "created_at": now, "updated_at": now
    }
    rk = room["_key"]
    ck = creator["_key"]
    cutoff = now - Membership.CONNECTION_TTL_MS
    mentioned = attachment.nil? ? RichText.mentioned_user_keys(body_html) : []
    to_mark = []
    push_to = []
    for m in members
      unread = m["user_id"] != ck && m["involvement"] != "invisible" && (m["connected_at"].nil? || m["connected_at"] < cutoff)
      next unless unread

      to_mark.push(m["_key"]) if m["unread_at"].nil?
      involved = m["involvement"] == "everything" || (m["involvement"] == "mentions" && mentioned.include?(m["user_id"]))
      push_to.push(m["user_id"]) if m["subscribed"] && involved
    end

    rows = nil
    for attempt in 0..5
      doc["_key"] = Ids.generate
      doc["html"] = MessagePresenter.render_new(doc, creator, room, base_url)
      doc["html_key"] = MessagePresenter.cache_key(doc)
      rows = @sdbql{
        INSERT #{doc} INTO messages
        FOR r IN rooms FILTER r._key == #{rk}
          UPDATE r WITH {updated_at: #{now}} IN rooms
          FOR k IN #{to_mark}
            UPDATE k WITH {unread_at: #{now}, updated_at: #{now}} IN memberships
      }
      break if rows.is_a?("array")
    end
    Db.array(rows)
    PushQueue.enqueue({"room_id": rk, "message_id": doc["_key"], "user_ids": push_to}) if push_to.length > 0
    {"message": doc, "members": members.map { |m| m["user_id"] }}
  end

  static def update_body(message, body_html)
    now = Clock.now
    plain = RichText.plain_text(body_html)
    Message.update(message["_key"], {
      "body": body_html, "plain_text": plain, "search_text": Stemmer.index_text(plain), "updated_at": now
    })
    Room.touch(message["room_id"], now)
    Message.find_hash(message["_key"])
  end

  # belongs_to :message, touch: true on boosts
  static def touch(key)
    k = key
    now = Clock.now
    @sdbql{ FOR m IN messages FILTER m._key == #{k} UPDATE m WITH {updated_at: #{now}} IN messages }
  end

  static def destroy_message(message)
    k = message["_key"]
    @sdbql{ FOR b IN boosts FILTER b.message_id == #{k} REMOVE b IN boosts }
    Attachments.delete_for(message["attachment"])
    @sdbql{ FOR m IN messages FILTER m._key == #{k} REMOVE m IN messages }
    Room.touch(message["room_id"])
  end

  # user.messages (User::Bannable#remove_banned_content)
  static def created_by(user_key)
    uk = user_key
    rows = @sdbql{ FOR m IN messages FILTER m.creator_id == #{uk} SORT m.created_at, m._key RETURN m }
    Db.array(rows)
  end

  static def destroy_all_in_room(room_key)
    rk = room_key
    rows = @sdbql{ FOR m IN messages FILTER m.room_id == #{rk} AND m.attachment != null RETURN m.attachment }
    for a in (Db.array(rows))
      Attachments.delete_for(a)
    end
    @sdbql{
      FOR m IN messages FILTER m.room_id == #{rk}
        FOR b IN boosts FILTER b.message_id == m._key
          REMOVE b IN boosts
    }
    @sdbql{ FOR m IN messages FILTER m.room_id == #{rk} REMOVE m IN messages }
  end

  static def save_html(key, html, html_key)
    k = key
    @sdbql{ FOR m IN messages FILTER m._key == #{k} UPDATE m WITH {html: #{html}, html_key: #{html_key}} IN messages }
  end

  # --- Message::Pagination ----------------------------------------------------------------

  static def last_page(room_key, size = 40)
    rk = room_key
    rows = @sdbql{
      FOR m IN messages FILTER m.room_id == #{rk}
        SORT m.created_at DESC, m._key DESC
        LIMIT #{size}
        RETURN m
    }
    Db.array(rows).reverse
  end

  static def page_before(room_key, message, size = 40)
    rk = room_key
    t = message["created_at"]
    rows = @sdbql{
      FOR m IN messages FILTER m.room_id == #{rk} AND m.created_at < #{t}
        SORT m.created_at DESC, m._key DESC
        LIMIT #{size}
        RETURN m
    }
    Db.array(rows).reverse
  end

  static def page_after(room_key, message, size = 40)
    rk = room_key
    t = message["created_at"]
    rows = @sdbql{
      FOR m IN messages FILTER m.room_id == #{rk} AND m.created_at > #{t}
        SORT m.created_at, m._key
        LIMIT #{size}
        RETURN m
    }
    Db.array(rows)
  end

  static def page_around(room_key, message)
    Message.page_before(room_key, message) + [message] + Message.page_after(room_key, message)
  end

  static def page_created_since(room_key, since)
    rk = room_key
    rows = @sdbql{
      FOR m IN messages FILTER m.room_id == #{rk} AND m.created_at > #{since}
        SORT m.created_at, m._key
        LIMIT 40
        RETURN m
    }
    Db.array(rows)
  end

  static def page_updated_since(room_key, since, excluded_keys)
    rk = room_key
    rows = @sdbql{
      FOR m IN messages FILTER m.room_id == #{rk} AND m.updated_at > #{since} AND m._key NOT IN #{excluded_keys}
        SORT m.created_at DESC, m._key DESC
        LIMIT 40
        RETURN m
    }
    Db.array(rows).reverse
  end

  static def count_in_room(room_key)
    rk = room_key
    rows = @sdbql{ RETURN LENGTH(FOR m IN messages FILTER m.room_id == #{rk} RETURN 1) }
    Db.array(rows).length > 0 ? rows[0] : 0
  end

  static def paged?(room_key)
    rk = room_key
    rows = @sdbql{ RETURN LENGTH(FOR m IN messages FILTER m.room_id == #{rk} LIMIT 41 RETURN 1) }
    Db.array(rows).length > 0 && rows[0] > Message.PAGE_SIZE
  end

  static def exists_before?(room_key, message)
    rk = room_key
    t = message["created_at"]
    rows = @sdbql{ RETURN LENGTH(FOR m IN messages FILTER m.room_id == #{rk} AND m.created_at < #{t} LIMIT 1 RETURN 1) }
    Db.array(rows).length > 0 && rows[0] > 0
  end

  static def exists_after?(room_key, message)
    rk = room_key
    t = message["created_at"]
    rows = @sdbql{ RETURN LENGTH(FOR m IN messages FILTER m.room_id == #{rk} AND m.created_at > #{t} LIMIT 1 RETURN 1) }
    Db.array(rows).length > 0 && rows[0] > 0
  end

  # --- Message::Searchable ----------------------------------------------------------------

  # Current.user.reachable_messages.search(query).last_page_of(100): every term must match
  # (FTS5's implicit AND), terms Porter-stemmed like the reference's tokenizer.
  static def search(user_key, query, size = 100)
    terms = Stemmer.query_terms(query)
    return [] if terms.length == 0

    uk = user_key
    first = terms[0]
    rows = @sdbql{
      LET room_ids = (FOR s IN memberships FILTER s.user_id == #{uk} RETURN s.room_id)
      FOR h IN (FULLTEXT("messages", "search_text", #{first}))
        LET m = h.doc
        FILTER m.room_id IN room_ids
        LET padded = CONCAT(" ", m.search_text, " ")
        FILTER LENGTH(FOR t IN #{terms} FILTER !CONTAINS(padded, CONCAT(" ", t, " ")) RETURN 1) == 0
        SORT m.created_at DESC, m._key DESC
        LIMIT #{size}
        RETURN m
    }
    Db.array(rows).reverse
  end

  # --- presentation ---------------------------------------------------------------------

  static def content_type(message)
    return "attachment" unless message["attachment"].nil?
    return "sound" unless Sounds.from_body(message["plain_text"]).nil?

    "text"
  end
end
