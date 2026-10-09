# Everything rooms/show draws, in as few round trips as possible.
class RoomPage
  static def room_for(user_key, room_key)
    found = Membership.with_room_for(user_key, room_key)
    found.nil? ? nil : found["room"]
  end

  static def base_url(req)
    proto = req["headers"]["x-forwarded-proto"] ?? (getenv("DISABLE_SSL").blank? ? "https" : "http")
    host = req["headers"]["x-forwarded-host"] ?? req["headers"]["host"] ?? "localhost"
    proto + "://" + host
  end

  # The room (a membership of the user's), the HTML of its last page of messages, the room's
  # member names for a direct room, and whether it shows the first-room invitation.
  #
  # SQLite joins the cached message HTML itself, so the page costs one string; messages
  # whose HTML is stale come back by key and are rendered (MessagePresenter) instead. The
  # signature is the page's html_keys: when the worker's last answer for the room has the
  # same, the HTML is not even joined.
  static def load(user_key, room_key, at_message_key)
    rk = str(room_key)
    cached = PageCache.get("room:" + rk)
    known = cached.nil? ? "" : cached["sig"]
    # The page size is written into the SQL: SQLite 3.53 runs this query four times slower with
    # a bound LIMIT (189 µs against 48).
    size = str(Message.PAGE_SIZE)
    page = Db.row("WITH room AS MATERIALIZED (SELECT r.* FROM memberships m JOIN rooms r ON r._key = m.room_id " +
      "WHERE m.room_id = ?1 AND m.user_id = ?2), " +
      "page AS MATERIALIZED (SELECT m._key AS k, m.html_key AS s, m.created_at AS t, m.html_key IS ?3 || m.updated_at AS ok " +
      "FROM messages m WHERE m.room_id = ?1 AND EXISTS (SELECT 1 FROM room) ORDER BY m.created_at DESC, m._key DESC LIMIT " + size + "), " +
      "facts AS (SELECT 'v:' || coalesce((SELECT group_concat(s, ',' ORDER BY t, k) FROM page), '') AS sig, " +
      "NOT EXISTS (SELECT 1 FROM page WHERE NOT ok) AS fresh, (SELECT _key FROM rooms ORDER BY created_at, _key LIMIT 1) AS original) " +
      "SELECT json_object('room', json((SELECT " + Db.json("rooms", "r") + " FROM room r)), " +
      "'keys', json((SELECT json_group_array(k ORDER BY t, k) FROM page)), 'sig', f.sig, " +
      "'same', json(CASE WHEN f.fresh AND f.sig = ?4 THEN 'true' ELSE 'false' END), " +
      "'html', CASE WHEN f.fresh AND f.sig != ?4 THEN coalesce((SELECT group_concat(m.html, char(10) ORDER BY p.t, p.k) " +
      "FROM page p JOIN messages m ON m._key = p.k), '') END, " +
      "'invitation', json(CASE WHEN f.original = ?1 AND (SELECT count(*) FROM (SELECT 1 FROM messages WHERE room_id = ?1 LIMIT " + size + " + 1)) <= " + size + " " +
      "THEN 'true' ELSE 'false' END), " +
      "'members', json(CASE WHEN (SELECT type FROM room) = 'Rooms::Direct' THEN (SELECT json_group_array(json_object('_key', u._key, 'name', u.name) " +
      "ORDER BY CAST(u._key AS INTEGER), u._key) FROM memberships s JOIN users u ON u._key = s.user_id WHERE s.room_id = ?1) ELSE '[]' END)) " +
      "AS j FROM facts f", [rk, user_key, MessagePresenter.VERSION + ":", known])
    return nil if page.nil? || page["room"].nil?

    if page["same"]
      page["html"] = cached["html"]
    elsif !page["html"].nil?
      PageCache.set("room:" + rk, {"sig": page["sig"], "html": page["html"]})
    end
    unless at_message_key.nil?
      target = Message.find_in_room(rk, at_message_key)
      unless target.nil?
        page["messages"] = Message.page_around(rk, target)
        page["html"] = nil
      end
    end
    if page["html"].nil? && page["messages"].nil?
      page["messages"] = Message.find_many_ordered(page["keys"])
    end
    page["display_name"] = RoomPage.display_name(page["room"], page["members"], user_key)
    page
  end

  static def messages_html(page, base_url)
    page["html"] ?? MessagePresenter.join(page["messages"], base_url)
  end

  # link_to [ :edit, @room ]: the edit route of the room's own type.
  static def edit_path(room)
    return "/rooms/directs/" + room["_key"] + "/edit" if Room.direct?(room)
    return "/rooms/closeds/" + room["_key"] + "/edit" if Room.closed?(room)

    "/rooms/opens/" + room["_key"] + "/edit"
  end

  static def display_name(room, members, user_key)
    return room["name"] unless Room.direct?(room)

    names = members.filter { |u| u["_key"] != user_key }.map { |u| u["name"] }
    return Room.to_sentence(names) if names.length > 0

    me = members.filter { |u| u["_key"] == user_key }
    me.length > 0 ? me[0]["name"] : ""
  end
end
