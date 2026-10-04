class Message < Model
  static PAGE_SIZE: Int = 40

  static def find_hash(key)
    return nil if key.nil?

    k = str(key)
    rows = @sdbql{ FOR m IN messages FILTER m._key == #{k} LIMIT 1 RETURN m }
    rows.is_a?("array") && rows.length > 0 ? rows[0] : nil
  end

  static def find_in_room(room_key, key)
    return nil if key.nil?

    k = str(key)
    rk = room_key
    rows = @sdbql{ FOR m IN messages FILTER m._key == #{k} AND m.room_id == #{rk} LIMIT 1 RETURN m }
    rows.is_a?("array") && rows.length > 0 ? rows[0] : nil
  end

  # Messages by key, in the order given.
  static def find_many_ordered(keys)
    return [] if keys.length == 0

    rows = @sdbql{ FOR k IN #{keys} FOR m IN messages FILTER m._key == k RETURN m }
    rows.is_a?("array") ? rows : []
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
    rows.is_a?("array") && rows.length > 0 ? rows[0] : nil
  end

  # room.messages.create_with_attachment!, then Room#receive (after_create_commit).
  static def create_message(room, creator_key, body_html, attachment, client_message_id)
    now = Clock.now
    plain = attachment.nil? ? RichText.plain_text(body_html) : ""
    plain = attachment["filename"] if plain.blank? && !attachment.nil?
    doc = {
      "room_id": room["_key"], "creator_id": creator_key,
      "client_message_id": client_message_id.blank? ? UUID.v4() : client_message_id,
      "body": attachment.nil? ? body_html : nil, "plain_text": plain ?? "",
      "search_text": Stemmer.index_text(plain ?? ""), "attachment": attachment,
      "created_at": now, "updated_at": now, "html": nil, "html_key": nil
    }
    created = Ids.create(Message, doc)
    message = Message.find_hash(created._key)
    Room.touch(room["_key"], now)
    Membership.mark_unread(room["_key"], creator_key, now)
    PushMessageJob.perform_later({"room_id": room["_key"], "message_id": message["_key"]}) rescue nil
    message
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

  static def destroy_all_in_room(room_key)
    rk = room_key
    rows = @sdbql{ FOR m IN messages FILTER m.room_id == #{rk} AND m.attachment != null RETURN m.attachment }
    for a in (rows.is_a?("array") ? rows : [])
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
    rows.is_a?("array") ? rows.reverse : []
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
    rows.is_a?("array") ? rows.reverse : []
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
    rows.is_a?("array") ? rows : []
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
    rows.is_a?("array") ? rows : []
  end

  static def page_updated_since(room_key, since, excluded_keys)
    rk = room_key
    rows = @sdbql{
      FOR m IN messages FILTER m.room_id == #{rk} AND m.updated_at > #{since} AND m._key NOT IN #{excluded_keys}
        SORT m.created_at DESC, m._key DESC
        LIMIT 40
        RETURN m
    }
    rows.is_a?("array") ? rows.reverse : []
  end

  static def count_in_room(room_key)
    rk = room_key
    rows = @sdbql{ RETURN LENGTH(FOR m IN messages FILTER m.room_id == #{rk} RETURN 1) }
    rows.is_a?("array") ? rows[0] : 0
  end

  static def paged?(room_key)
    rk = room_key
    rows = @sdbql{ RETURN LENGTH(FOR m IN messages FILTER m.room_id == #{rk} LIMIT 41 RETURN 1) }
    rows.is_a?("array") && rows[0] > Message.PAGE_SIZE
  end

  static def exists_before?(room_key, message)
    rk = room_key
    t = message["created_at"]
    rows = @sdbql{ RETURN LENGTH(FOR m IN messages FILTER m.room_id == #{rk} AND m.created_at < #{t} LIMIT 1 RETURN 1) }
    rows.is_a?("array") && rows[0] > 0
  end

  static def exists_after?(room_key, message)
    rk = room_key
    t = message["created_at"]
    rows = @sdbql{ RETURN LENGTH(FOR m IN messages FILTER m.room_id == #{rk} AND m.created_at > #{t} LIMIT 1 RETURN 1) }
    rows.is_a?("array") && rows[0] > 0
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
    rows.is_a?("array") ? rows.reverse : []
  end

  # --- presentation ---------------------------------------------------------------------

  static def content_type(message)
    return "attachment" unless message["attachment"].nil?
    return "sound" unless Sounds.from_body(message["plain_text"]).nil?

    "text"
  end
end
