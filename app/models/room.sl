# Rooms::Open, Rooms::Closed and Rooms::Direct share this collection; `type` keeps the
# reference's class names.
class Room < Model
  static OPEN: String = "Rooms::Open"
  static CLOSED: String = "Rooms::Closed"
  static DIRECT: String = "Rooms::Direct"

  static def find_hash(key)
    return nil if key.nil?

    Db.find_row("rooms", key)
  end

  static def open?(room)
    room["type"] == Room.OPEN
  end

  static def closed?(room)
    room["type"] == Room.CLOSED
  end

  static def direct?(room)
    room["type"] == Room.DIRECT
  end

  # dom_id(room): "rooms_open_1", "rooms_closed_1", "rooms_direct_1"
  static def dom_id(room, prefix = nil)
    id = room["type"].downcase.replace("::", "_") + "_" + room["_key"]
    prefix.nil? ? id : prefix + "_" + id
  end

  static def default_involvement(room)
    Room.direct?(room) ? "everything" : "mentions"
  end

  # Room.create_for: the room, then memberships for the given users.
  static def create_for(type, name, creator_id, user_ids)
    now = Clock.now
    hash = Ids.create("rooms", {"name": name, "type": type, "creator_id": creator_id, "created_at": now, "updated_at": now})
    Membership.grant(hash, user_ids)
    Membership.grant(hash, User.active_ordered.map { |u| u["_key"] }) if type == Room.OPEN
    hash
  end

  # Room.original: the first room ever created.
  static def original
    Db.row("SELECT " + Db.json("rooms", "r") + " AS j FROM rooms r ORDER BY r.created_at, r._key LIMIT 1")
  end

  static def original_key
    Db.value("SELECT _key AS v FROM rooms ORDER BY created_at, _key LIMIT 1")
  end

  # Current.user.rooms.original
  static def default_for_user(user_key)
    Db.row("SELECT " + Db.json("rooms", "r") + " AS j FROM memberships m JOIN rooms r ON r._key = m.room_id WHERE m.user_id = ? " +
           "ORDER BY r.created_at, r._key LIMIT 1", [user_key])
  end

  # Current.user.rooms.last (RoomsController#index)
  static def last_for_user(user_key)
    Db.row("SELECT " + Db.json("rooms", "r") + " AS j FROM memberships m JOIN rooms r ON r._key = m.room_id WHERE m.user_id = ? " +
           "ORDER BY r.created_at DESC, r._key DESC LIMIT 1", [user_key])
  end

  static def touch(key, now = nil)
    Db.exec("UPDATE rooms SET updated_at = ? WHERE _key = ?", [now ?? Clock.now, str(key)])
  end

  static def open_room_keys
    Db.rows("SELECT json_quote(_key) AS j FROM rooms WHERE type = 'Rooms::Open'")
  end

  # Becoming an open room grants everyone access (Rooms::Open after_save_commit).
  static def change_type(room, type)
    return room if room["type"] == type

    Db.update_row("rooms", room["_key"], {"type": type, "updated_at": Clock.now})
    updated = Room.find_hash(room["_key"])
    Membership.grant(updated, User.active_ordered.map { |u| u["_key"] }) if type == Room.OPEN
    updated
  end

  # @room.becomes!(type).update!(name:): one write, then Rooms::Open's grant to everyone
  # when the room has just become open.
  static def update_settings(room, type, name)
    k = room["_key"]
    Db.update_row("rooms", k, {"type": type, "name": name ?? room["name"], "updated_at": Clock.now})
    updated = Room.find_hash(k)
    Membership.grant(updated, User.active_ordered.map { |u| u["_key"] }) if type == Room.OPEN && room["type"] != Room.OPEN
    updated
  end

  # The users of a room in membership order (room.users), for direct room sidebars.
  static def users_by_membership(room_key)
    Db.rows("SELECT " + Db.json("users", "u") + " AS j FROM memberships m JOIN users u ON u._key = m.user_id WHERE m.room_id = ? " +
            "ORDER BY m.created_at, m._key", [room_key])
  end

  static def rename(room, name)
    Db.update_row("rooms", room["_key"], {"name": name, "updated_at": Clock.now})
    Room.find_hash(room["_key"])
  end

  # Room#destroy: memberships, messages (with their boosts and attachments) and the room.
  static def destroy_room(room)
    k = room["_key"]
    Message.destroy_all_in_room(k)
    Db.exec("DELETE FROM memberships WHERE room_id = ?", [k])
    Db.delete_row("rooms", k)
  end

  # The users of a room, ordered by name.
  static def users(room_key)
    Db.rows("SELECT " + Db.json("users", "u") + " AS j FROM memberships m JOIN users u ON u._key = m.user_id WHERE m.room_id = ? " +
            "ORDER BY CAST(u._key AS INTEGER), u._key", [room_key])
  end

  static def user_keys(room_key)
    Db.rows("SELECT json_quote(user_id) AS j FROM memberships WHERE room_id = ?", [room_key])
  end

  # Rooms::Direct.find_or_create_for: the direct room whose members are exactly these users.
  static def find_direct_for(user_keys)
    keys = user_keys.uniq
    binds = [keys[0], keys.length] + keys
    Db.row("SELECT " + Db.json("rooms", "r") + " AS j FROM memberships m JOIN rooms r ON r._key = m.room_id AND r.type = 'Rooms::Direct' " +
           "WHERE m.user_id = ? AND (SELECT count(*) FROM memberships o WHERE o.room_id = r._key) = ? " +
           "AND NOT EXISTS (SELECT 1 FROM memberships o WHERE o.room_id = r._key AND o.user_id NOT IN (" + Db.marks(keys) + ")) " +
           "LIMIT 1", binds)
  end

  # RoomsHelper#room_display_name
  static def display_name(room, for_user_key)
    return room["name"] unless Room.direct?(room)

    others = Room.users(room["_key"]).filter { |u| u["_key"] != for_user_key }
    names = others.map { |u| u["name"] }
    return Room.to_sentence(names) if names.length > 0
    return "" if for_user_key.nil?

    me = User.find_hash(for_user_key)
    me.nil? ? "" : me["name"]
  end

  # What a message shows for its room: Room.display_name(room, nil), from the names of the
  # room's users in Room.users order, without a query.
  static def message_room_name(room, user_names)
    Room.direct?(room) ? Room.to_sentence(user_names) : room["name"]
  end

  # The room and its users' names, in Room.users order: what Room.message_room_name needs.
  static def with_member_names(key)
    Db.row("SELECT json_object('room', " + Db.json("rooms", "r") + ", 'names', json((SELECT json_group_array(u.name ORDER BY " +
           "CAST(u._key AS INTEGER), u._key) FROM memberships m JOIN users u ON u._key = m.user_id WHERE m.room_id = r._key))) " +
           "AS j FROM rooms r WHERE r._key = ?", [str(key)])
  end

  static def to_sentence(words)
    return "" if words.length == 0
    return words[0] if words.length == 1
    return words[0] + " and " + words[1] if words.length == 2

    words.take(words.length - 1).join(", ") + ", and " + words.last
  end
end
