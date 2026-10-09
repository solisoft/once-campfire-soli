class Membership < Model
  static INVOLVEMENTS: Array = ["invisible", "nothing", "mentions", "everything"]
  static CONNECTION_TTL_MS: Int = 60000

  # memberships.grant_to: insert_all, skipping users who are already members.
  static def grant(room, user_keys)
    return nil if user_keys.length == 0

    rk = room["_key"]
    involvement = Room.default_involvement(room)
    now = Clock.now
    existing = Room.user_keys(rk)
    i = 0
    docs = user_keys.uniq.filter { |k| !existing.include?(k) }.map { |k|
      i += 1
      {"_key": Ids.generate + str(i), "room_id": rk, "user_id": k, "involvement": involvement, "unread_at": nil,
       "connected_at": nil, "connections": 0, "created_at": now, "updated_at": now}
    }
    return nil if docs.length == 0

    Db.transaction(fn() {
      for doc in docs
        Db.insert("memberships", doc)
      end
    })
  end

  static def grant_open_rooms_to(user_key)
    now = Clock.now
    Db.exec("INSERT INTO memberships (_key, room_id, user_id, involvement, connections, created_at, updated_at) " +
            "SELECT ? || r._key, r._key, ?, 'mentions', 0, ?, ? FROM rooms r WHERE r.type = 'Rooms::Open' " +
            "AND NOT EXISTS (SELECT 1 FROM memberships m WHERE m.room_id = r._key AND m.user_id = ?)",
            [Ids.generate, user_key, now, now, user_key])
  end

  static def revoke(room_key, user_keys)
    return nil if user_keys.length == 0

    Db.exec("DELETE FROM memberships WHERE room_id = ? AND user_id IN (" + Db.marks(user_keys) + ")", [room_key] + user_keys)
  end

  static def find_hash(key)
    Db.find_row("memberships", key)
  end

  static def find_for(user_key, room_key)
    return nil if user_key.nil? || room_key.nil?

    Db.row("SELECT " + Db.json("memberships", "m") + " AS j FROM memberships m WHERE m.room_id = ? AND m.user_id = ?", [str(room_key), user_key])
  end

  # The membership and its room in one round trip (RoomScoped#set_room).
  static def with_room_for(user_key, room_key)
    return nil if user_key.nil? || room_key.nil?

    Db.row("SELECT json_object('membership', " + Db.json("memberships", "m") + ", 'room', " + Db.json("rooms", "r") + ") AS j " +
           "FROM memberships m JOIN rooms r ON r._key = m.room_id WHERE m.room_id = ? AND m.user_id = ?",
           [str(room_key), user_key])
  end

  static def set_involvement(membership, involvement)
    Db.update_row("memberships", membership["_key"], {"involvement": involvement, "updated_at": Clock.now})
  end

  static def read(membership_key)
    Db.update_row("memberships", membership_key, {"unread_at": nil, "updated_at": Clock.now})
  end

  static def connected?(membership, now = nil)
    t = now ?? Clock.now
    !membership["connected_at"].nil? && membership["connected_at"] >= t - Membership.CONNECTION_TTL_MS
  end

  # Membership::Connectable#present
  static def present(membership)
    now = Clock.now
    k = membership["_key"]
    connections = Membership.connected?(membership, now) ? membership["connections"] + 1 : 1
    Db.update_row("memberships", k, {"connections": connections, "connected_at": now, "unread_at": nil})
  end

  # Membership::Connectable#disconnected
  static def disconnected(membership)
    now = Clock.now
    k = membership["_key"]
    connections = Membership.connected?(membership, now) ? membership["connections"] - 1 : 0
    if connections < 1
      Db.update_row("memberships", k, {"connections": connections, "connected_at": nil, "updated_at": now})
    else
      Db.update_row("memberships", k, {"connections": connections, "updated_at": now})
    end
  end

  # Membership::Connectable#refresh_connection
  static def refresh_connection(membership)
    now = Clock.now
    k = membership["_key"]
    connections = Membership.connected?(membership, now) ? membership["connections"] : membership["connections"] + 1
    Db.update_row("memberships", k, {"connections": connections, "connected_at": now, "updated_at": now})
  end

  # Room#unread_memberships: visible, disconnected members other than the author.
  static def mark_unread(room_key, author_key, at)
    now = Clock.now
    Db.exec("UPDATE memberships SET unread_at = ?, updated_at = ? WHERE room_id = ? AND user_id != ? " +
            "AND involvement IS NOT 'invisible' AND (connected_at IS NULL OR connected_at < ?)",
            [at, now, room_key, author_key, now - Membership.CONNECTION_TTL_MS])
  end

  # Memberships of a user, each with its room, rooms ordered by LOWER(name).
  static def with_rooms_for(user_key, visible_only = false)
    visible = visible_only ? " AND m.involvement IS NOT 'invisible'" : ""
    Db.rows("SELECT json_object(" + Db.fields("memberships", "m") + ", 'room', " + Db.json("rooms", "r") + ") AS j " +
            "FROM memberships m JOIN rooms r ON r._key = m.room_id WHERE m.user_id = ?" + visible +
            " ORDER BY lower(r.name), r._key", [user_key])
  end

  # user.memberships.without_direct_rooms.delete_all
  static def delete_for_user_without_direct_rooms(user_key)
    Db.exec("DELETE FROM memberships WHERE user_id = ? AND room_id NOT IN (SELECT _key FROM rooms WHERE type = 'Rooms::Direct')",
            [user_key])
  end

  # user.rooms.without_directs.ordered
  static def rooms_without_directs_for(user_key)
    Db.rows("SELECT " + Db.json("rooms", "r") + " AS j FROM memberships m JOIN rooms r ON r._key = m.room_id " +
            "WHERE m.user_id = ? AND r.type != 'Rooms::Direct' ORDER BY lower(r.name), r._key", [user_key])
  end

  # Current.user.memberships.with_ordered_room for users/profiles/show: each membership with
  # its room and, for a direct room, the names of the other members in users' id order (the
  # order room.users comes back in), for room_display_name.
  static def with_rooms_and_other_names_for(user_key)
    Db.rows("SELECT json_object(" + Db.fields("memberships", "m") + ", 'room', " + Db.json("rooms", "r") + ", 'other_names', json(CASE WHEN r.type != 'Rooms::Direct' " +
            "THEN '[]' ELSE (SELECT json_group_array(u.name ORDER BY CAST(u._key AS INTEGER)) FROM memberships o " +
            "JOIN users u ON u._key = o.user_id WHERE o.room_id = r._key AND o.user_id != ?) END)) AS j " +
            "FROM memberships m JOIN rooms r ON r._key = m.room_id WHERE m.user_id = ? ORDER BY lower(r.name), r._key",
            [user_key, user_key])
  end
end
