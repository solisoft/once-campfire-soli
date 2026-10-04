# What Rooms::OpensController, Rooms::ClosedsController and Rooms::DirectsController share:
# the room scopes they reach rooms through, the sidebar fragments they broadcast, and the
# turbo_rails/frame layout their frame requests get.
class RoomForms
  static DEFAULT_ROOM_NAME: String = "New room"

  # room_scope.find_by(id:): open and closed rooms (without_directs), or direct rooms only.
  static def find_room(user_key, room_key, directs)
    found = Membership.with_room_for(user_key, room_key)
    return nil if found.nil?

    room = found["room"]
    return nil if Room.direct?(room) != directs

    room
  end

  # RoomsController#ensure_permission_to_create_rooms
  static def can_create?(user, account)
    User.administrator?(user) || !Account.restrict_room_creation?(account)
  end

  # users/sidebars/rooms/_shared, rendered once for everyone it goes to.
  static def shared_html(room)
    render_partial("users/sidebars/rooms/shared", {"room": room, "unread": false})
  end

  # Rooms::OpensController#broadcast_create_room / Rooms::ClosedsController#broadcast_create_room
  static def broadcast_created(room)
    stream = TurboStream.prepend("shared_rooms", RoomForms.shared_html(room))
    if Room.open?(room)
      Cable.broadcast_stream("rooms", stream)
    else
      for user_key in Room.user_keys(room["_key"])
        Cable.broadcast_stream("user:" + user_key + ":rooms", stream)
      end
    end
  end

  # broadcast_update_room: the sidebar entry replaced, for everyone (open) or each member (closed).
  static def broadcast_updated(room)
    stream = TurboStream.replace(Room.dom_id(room, "list"), RoomForms.shared_html(room))
    if Room.open?(room)
      Cable.broadcast_stream("rooms", stream)
    else
      for user_key in Room.user_keys(room["_key"])
        Cable.broadcast_stream("user:" + user_key + ":rooms", stream)
      end
    end
  end

  # Rooms::DirectsController#broadcast_create_room: each member's own sidebar entry.
  static def broadcast_direct_created(room)
    members = Present.users(Room.users_by_membership(room["_key"]))
    for member in members
      others = members.filter { |u| u["_key"] != member["_key"] }
      others = [member] if others.length == 0
      membership = {"room": room, "unread_at": nil, "others": others}
      html = render_partial("users/sidebars/rooms/direct", {"membership": membership})
      Cable.broadcast_stream("user:" + member["_key"] + ":rooms", TurboStream.prepend("direct_rooms", html))
    end
  end

  # The selected users' keys, from user_ids[] in the body or the query string (button_to).
  static def user_ids(params, req)
    ids = params["user_ids"] ?? params["user_ids[]"]
    if ids.nil? && !req["query"].nil?
      ids = req["query"]["user_ids"] ?? req["query"]["user_ids[]"]
    end
    return [] if ids.nil?
    return [str(ids)] unless ids.is_a?("array")

    ids.map { |i| str(i) }.filter { |i| !i.blank? }
  end

  # turbo-rails' turbo_rails/frame layout: a frame request gets its frame, the csrf meta tags
  # and nothing of the application layout.
  static def frame_body(body, csrf)
    "<html>\n  <head>\n    <meta name=\"csrf-param\" content=\"_csrf_token\" />\n<meta name=\"csrf-token\" content=\"" + csrf +
      "\" />\n    \n  </head>\n  <body>\n    " + body + "  </body>\n</html>\n"
  end

  static def frame_request?(req)
    !(req["headers"]["turbo-frame"] ?? "").blank?
  end
end
