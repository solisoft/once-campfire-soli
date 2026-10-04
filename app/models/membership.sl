class Membership < Model
  static INVOLVEMENTS: Array = ["invisible", "nothing", "mentions", "everything"]
  static CONNECTION_TTL_MS: Int = 60000

  # memberships.grant_to: insert_all, skipping users who are already members.
  static def grant(room, user_keys)
    return nil if user_keys.length == 0

    rk = room["_key"]
    involvement = Room.default_involvement(room)
    now = Clock.now
    existing = @sdbql{ FOR m IN memberships FILTER m.room_id == #{rk} RETURN m.user_id }
    existing = [] unless existing.is_a?("array")
    i = 0
    docs = user_keys.uniq.filter { |k| !existing.include?(k) }.map { |k|
      i += 1
      {"_key": Ids.generate + str(i), "room_id": rk, "user_id": k, "involvement": involvement, "unread_at": nil,
       "connected_at": nil, "connections": 0, "created_at": now, "updated_at": now}
    }
    return nil if docs.length == 0

    @sdbql{ FOR d IN #{docs} INSERT d INTO memberships }
  end

  static def grant_open_rooms_to(user_key)
    now = Clock.now
    base = Ids.generate
    uk = user_key
    @sdbql{
      FOR r IN rooms FILTER r.type == "Rooms::Open"
        LET taken = LENGTH(FOR m IN memberships FILTER m.room_id == r._key AND m.user_id == #{uk} LIMIT 1 RETURN 1)
        FILTER taken == 0
        INSERT {_key: CONCAT(#{base}, r._key), room_id: r._key, user_id: #{uk}, involvement: "mentions", unread_at: null,
                connected_at: null, connections: 0, created_at: #{now}, updated_at: #{now}} INTO memberships
    }
  end

  static def revoke(room_key, user_keys)
    return nil if user_keys.length == 0

    rk = room_key
    @sdbql{ FOR m IN memberships FILTER m.room_id == #{rk} AND m.user_id IN #{user_keys} REMOVE m IN memberships }
  end

  static def find_hash(key)
    k = key
    rows = @sdbql{ FOR m IN memberships FILTER m._key == #{k} LIMIT 1 RETURN m }
    rows.is_a?("array") && rows.length > 0 ? rows[0] : nil
  end

  static def find_for(user_key, room_key)
    return nil if user_key.nil? || room_key.nil?

    uk = user_key
    rk = str(room_key)
    rows = @sdbql{ FOR m IN memberships FILTER m.room_id == #{rk} AND m.user_id == #{uk} LIMIT 1 RETURN m }
    rows.is_a?("array") && rows.length > 0 ? rows[0] : nil
  end

  # The membership and its room in one round trip (RoomScoped#set_room).
  static def with_room_for(user_key, room_key)
    return nil if user_key.nil? || room_key.nil?

    uk = user_key
    rk = str(room_key)
    rows = @sdbql{
      FOR m IN memberships FILTER m.room_id == #{rk} AND m.user_id == #{uk}
        FOR r IN rooms FILTER r._key == m.room_id
          LIMIT 1
          RETURN {membership: m, room: r}
    }
    rows.is_a?("array") && rows.length > 0 ? rows[0] : nil
  end

  static def set_involvement(membership, involvement)
    k = membership["_key"]
    now = Clock.now
    @sdbql{ FOR m IN memberships FILTER m._key == #{k} UPDATE m WITH {involvement: #{involvement}, updated_at: #{now}} IN memberships }
  end

  static def read(membership_key)
    k = membership_key
    now = Clock.now
    @sdbql{ FOR m IN memberships FILTER m._key == #{k} UPDATE m WITH {unread_at: null, updated_at: #{now}} IN memberships }
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
    @sdbql{
      FOR m IN memberships FILTER m._key == #{k}
        UPDATE m WITH {connections: #{connections}, connected_at: #{now}, unread_at: null} IN memberships
    }
  end

  # Membership::Connectable#disconnected
  static def disconnected(membership)
    now = Clock.now
    k = membership["_key"]
    connections = Membership.connected?(membership, now) ? membership["connections"] - 1 : 0
    if connections < 1
      @sdbql{ FOR m IN memberships FILTER m._key == #{k} UPDATE m WITH {connections: #{connections}, connected_at: null, updated_at: #{now}} IN memberships }
    else
      @sdbql{ FOR m IN memberships FILTER m._key == #{k} UPDATE m WITH {connections: #{connections}, updated_at: #{now}} IN memberships }
    end
  end

  # Membership::Connectable#refresh_connection
  static def refresh_connection(membership)
    now = Clock.now
    k = membership["_key"]
    connections = Membership.connected?(membership, now) ? membership["connections"] : membership["connections"] + 1
    @sdbql{ FOR m IN memberships FILTER m._key == #{k} UPDATE m WITH {connections: #{connections}, connected_at: #{now}, updated_at: #{now}} IN memberships }
  end

  # Room#unread_memberships: visible, disconnected members other than the author.
  static def mark_unread(room_key, author_key, at)
    rk = room_key
    ak = author_key
    cutoff = Clock.now - Membership.CONNECTION_TTL_MS
    now = Clock.now
    @sdbql{
      FOR m IN memberships
        FILTER m.room_id == #{rk} AND m.user_id != #{ak} AND m.involvement != "invisible"
        FILTER m.connected_at == null OR m.connected_at < #{cutoff}
        UPDATE m WITH {unread_at: #{at}, updated_at: #{now}} IN memberships
    }
  end

  # Memberships of a user, each with its room, rooms ordered by LOWER(name).
  static def with_rooms_for(user_key, visible_only = false)
    uk = user_key
    rows = nil
    if visible_only
      rows = @sdbql{
        FOR m IN memberships FILTER m.user_id == #{uk} AND m.involvement != "invisible"
          FOR r IN rooms FILTER r._key == m.room_id
            SORT LOWER(r.name), r._key
            RETURN MERGE(m, {room: r})
      }
    else
      rows = @sdbql{
        FOR m IN memberships FILTER m.user_id == #{uk}
          FOR r IN rooms FILTER r._key == m.room_id
            SORT LOWER(r.name), r._key
            RETURN MERGE(m, {room: r})
      }
    end
    rows.is_a?("array") ? rows : []
  end
end
