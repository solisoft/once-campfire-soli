# Rooms::Open, Rooms::Closed and Rooms::Direct share this collection; `type` keeps the
# reference's class names.
class Room < Model
  static OPEN: String = "Rooms::Open"
  static CLOSED: String = "Rooms::Closed"
  static DIRECT: String = "Rooms::Direct"

  static def find_hash(key)
    return nil if key.nil?

    k = str(key)
    rows = @sdbql{ FOR r IN rooms FILTER r._key == #{k} LIMIT 1 RETURN r }
    Db.first(rows)
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
    room = Ids.create(Room, {"name": name, "type": type, "creator_id": creator_id, "created_at": now, "updated_at": now})
    hash = Room.find_hash(room._key)
    Membership.grant(hash, user_ids)
    Membership.grant(hash, User.active_ordered.map { |u| u["_key"] }) if type == Room.OPEN
    hash
  end

  # Room.original: the first room ever created.
  static def original
    rows = @sdbql{ FOR r IN rooms SORT r.created_at, r._key LIMIT 1 RETURN r }
    Db.first(rows)
  end

  static def original_key
    rows = @sdbql{ FOR r IN rooms SORT r.created_at, r._key LIMIT 1 RETURN r._key }
    Db.first(rows)
  end

  # Current.user.rooms.original
  static def default_for_user(user_key)
    uk = user_key
    rows = @sdbql{
      FOR m IN memberships FILTER m.user_id == #{uk}
        FOR r IN rooms FILTER r._key == m.room_id
          SORT r.created_at, r._key
          LIMIT 1
          RETURN r
    }
    Db.first(rows)
  end

  # Current.user.rooms.last (RoomsController#index)
  static def last_for_user(user_key)
    uk = user_key
    rows = @sdbql{
      FOR m IN memberships FILTER m.user_id == #{uk}
        FOR r IN rooms FILTER r._key == m.room_id
          SORT r.created_at DESC, r._key DESC
          LIMIT 1
          RETURN r
    }
    Db.first(rows)
  end

  static def touch(key, now = nil)
    t = now ?? Clock.now
    k = key
    @sdbql{ FOR r IN rooms FILTER r._key == #{k} UPDATE r WITH {updated_at: #{t}} IN rooms }
  end

  static def open_room_keys
    rows = @sdbql{ FOR r IN rooms FILTER r.type == "Rooms::Open" RETURN r._key }
    Db.array(rows)
  end

  # Becoming an open room grants everyone access (Rooms::Open after_save_commit).
  static def change_type(room, type)
    return room if room["type"] == type

    Room.update(room["_key"], {"type": type, "updated_at": Clock.now})
    updated = Room.find_hash(room["_key"])
    Membership.grant(updated, User.active_ordered.map { |u| u["_key"] }) if type == Room.OPEN
    updated
  end

  # @room.becomes!(type).update!(name:): one write, then Rooms::Open's grant to everyone
  # when the room has just become open.
  static def update_settings(room, type, name)
    k = room["_key"]
    now = Clock.now
    new_name = name ?? room["name"]
    @sdbql{ FOR r IN rooms FILTER r._key == #{k} UPDATE r WITH {type: #{type}, name: #{new_name}, updated_at: #{now}} IN rooms }
    updated = Room.find_hash(k)
    Membership.grant(updated, User.active_ordered.map { |u| u["_key"] }) if type == Room.OPEN && room["type"] != Room.OPEN
    updated
  end

  # The users of a room in membership order (room.users), for direct room sidebars.
  static def users_by_membership(room_key)
    k = room_key
    rows = @sdbql{
      FOR m IN memberships FILTER m.room_id == #{k}
        FOR u IN users FILTER u._key == m.user_id
          SORT m.created_at, m._key
          RETURN u
    }
    Db.array(rows)
  end

  static def rename(room, name)
    Room.update(room["_key"], {"name": name, "updated_at": Clock.now})
    Room.find_hash(room["_key"])
  end

  # Room#destroy: memberships, messages (with their boosts and attachments) and the room.
  static def destroy_room(room)
    k = room["_key"]
    Message.destroy_all_in_room(k)
    @sdbql{ FOR m IN memberships FILTER m.room_id == #{k} REMOVE m IN memberships }
    @sdbql{ FOR r IN rooms FILTER r._key == #{k} REMOVE r IN rooms }
  end

  # The users of a room, ordered by name.
  static def users(room_key)
    k = room_key
    rows = @sdbql{
      FOR m IN memberships FILTER m.room_id == #{k}
        FOR u IN users FILTER u._key == m.user_id
          SORT TO_NUMBER(u._key), u._key
          RETURN u
    }
    Db.array(rows)
  end

  static def user_keys(room_key)
    k = room_key
    rows = @sdbql{ FOR m IN memberships FILTER m.room_id == #{k} RETURN m.user_id }
    Db.array(rows)
  end

  # Rooms::Direct.find_or_create_for: the direct room whose members are exactly these users.
  static def find_direct_for(user_keys)
    keys = user_keys.uniq
    n = keys.length
    first = keys[0]
    rows = @sdbql{
      FOR m IN memberships FILTER m.user_id == #{first}
        FOR r IN rooms FILTER r._key == m.room_id AND r.type == "Rooms::Direct"
          LET members = (FOR o IN memberships FILTER o.room_id == r._key RETURN o.user_id)
          FILTER LENGTH(members) == #{n} AND LENGTH(MINUS(members, #{keys})) == 0
          LIMIT 1
          RETURN r
    }
    Db.first(rows)
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

  static def to_sentence(words)
    return "" if words.length == 0
    return words[0] if words.length == 1
    return words[0] + " and " + words[1] if words.length == 2

    words.take(words.length - 1).join(", ") + ", and " + words.last
  end
end
