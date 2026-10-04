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
  # SoliDB joins the cached message HTML itself, so the page costs one string; messages
  # whose HTML is stale come back by key and are rendered (MessagePresenter) instead.
  static def load(user_key, room_key, at_message_key)
    uk = user_key
    rk = str(room_key)
    size = Message.PAGE_SIZE
    version = MessagePresenter.VERSION + ":"
    cached = PageCache.get("room:" + rk)
    known = cached.nil? ? "" : cached["sig"]
    rows = @sdbql{
      LET room = FIRST(
        FOR m IN memberships FILTER m.room_id == #{rk} AND m.user_id == #{uk}
          FOR r IN rooms FILTER r._key == m.room_id
            RETURN r
      )
      LET page = room == null ? [] : REVERSE(
        FOR m IN messages FILTER m.room_id == #{rk}
          SORT m.created_at DESC, m._key DESC
          LIMIT #{size}
          RETURN {k: m._key, s: m.html_key, html: m.html_key == CONCAT(#{version}, m.updated_at) ? m.html : null}
      )
      LET stale = (FOR p IN page FILTER p.html == null RETURN p.k)
      LET sig = MD5(CONCAT_SEPARATOR(",", page[*].s))
      LET original = FIRST(FOR r IN rooms SORT r.created_at, r._key LIMIT 1 RETURN r._key)
      LET paged = original == #{rk} ? LENGTH(FOR m IN messages FILTER m.room_id == #{rk} LIMIT 41 RETURN 1) > #{size} : true
      LET members = room != null && room.type == "Rooms::Direct" ?
        (FOR s IN memberships FILTER s.room_id == #{rk} FOR u IN users FILTER u._key == s.user_id SORT TO_NUMBER(u._key), u._key RETURN {_key: u._key, name: u.name}) : []
      LET fresh = LENGTH(stale) == 0
      RETURN {room: room, keys: page[*].k, stale: stale, sig: sig, same: fresh AND sig == #{known},
              html: fresh AND sig != #{known} ? CONCAT_SEPARATOR("\n", page[*].html) : null,
              invitation: original == #{rk} AND !paged, members: members}
    }
    return nil unless Db.array(rows).length > 0 && !rows[0]["room"].nil?

    page = rows[0]
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
