# users/sidebars#show in one round trip: the user's visible memberships with their rooms,
# the members of each direct room, and the people to offer a first ping with.
class Sidebar
  static DIRECT_PLACEHOLDERS: Int = 20

  # known: the signature of the data the caller already rendered; when it still holds, the
  # rows don't come back ("same": true).
  # Placeholders are SLICEd rather than LIMITed: a LIMIT taken from a variable comes back
  # empty on a collection scan (solidb, 2026-10).
  static def load(user_key, known = "")
    uk = user_key
    limit = Sidebar.DIRECT_PLACEHOLDERS
    rows = @sdbql{
      LET memberships = (
        FOR m IN memberships FILTER m.user_id == #{uk} AND m.involvement != "invisible"
          FOR r IN rooms FILTER r._key == m.room_id
            LET members = r.type == "Rooms::Direct" ? (
              FOR o IN memberships FILTER o.room_id == r._key
                FOR u IN users FILTER u._key == o.user_id
                  SORT TO_NUMBER(u._key), u._key
                  RETURN {_key: u._key, name: u.name, updated_at: u.updated_at}
            ) : []
            SORT LOWER(r.name), r._key
            RETURN {_key: m._key, unread_at: m.unread_at, updated_at: m.updated_at, room: r, members: members}
      )
      LET direct_user_ids = UNIQUE(FLATTEN(FOR m IN memberships FILTER m.room.type == "Rooms::Direct" RETURN m.members[*]._key))
      LET in_directs = (
        FOR m IN memberships FILTER m.user_id == #{uk}
          FOR r IN rooms FILTER r._key == m.room_id AND r.type == "Rooms::Direct"
            FOR o IN memberships FILTER o.room_id == r._key
              RETURN DISTINCT o.user_id
      )
      LET excluded = UNION_DISTINCT(in_directs, [#{uk}])
      LET placeholder_limit = MAX([#{limit} - LENGTH(excluded), 0])
      LET placeholders = SLICE((
        FOR u IN users FILTER u.status == "active" AND u._key NOT IN excluded
          SORT u.created_at, u._key
          RETURN u
      ), 0, placeholder_limit)
      LET sig = MD5(TO_STRING([memberships, placeholders]))
      RETURN sig == #{known} ? {same: true, sig: sig} : {same: false, sig: sig, memberships: memberships, placeholders: placeholders}
    }
    return {"same": false, "sig": "", "memberships": [], "placeholders": []} unless Db.array(rows).length > 0

    rows[0]
  end
end
