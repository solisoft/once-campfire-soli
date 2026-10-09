# users/sidebars#show in one query: the user's visible memberships with their rooms, the
# members of each direct room, and the people to offer a first ping with.
class Sidebar
  static DIRECT_PLACEHOLDERS: Int = 20

  # known: the signature of the data the caller already rendered; when it still holds, the
  # rows aren't parsed ("same": true).
  static def load(user_key, known = "")
    text = Db.value("WITH mine AS (SELECT * FROM memberships WHERE user_id = ?1), " +
      "excluded AS (SELECT o.user_id AS id FROM mine m JOIN rooms r ON r._key = m.room_id AND r.type = 'Rooms::Direct' " +
      "JOIN memberships o ON o.room_id = r._key UNION SELECT ?1), " +
      "list AS (SELECT json_object('_key', m._key, 'unread_at', m.unread_at, 'updated_at', m.updated_at, 'room', " + Db.json("rooms", "r") + ", " +
      "'members', json(CASE WHEN r.type = 'Rooms::Direct' THEN (SELECT json_group_array(json_object('_key', u._key, 'name', u.name, " +
      "'updated_at', u.updated_at) ORDER BY CAST(u._key AS INTEGER), u._key) FROM memberships o JOIN users u ON u._key = o.user_id " +
      "WHERE o.room_id = r._key) ELSE '[]' END)) AS j, lower(r.name) AS n, r._key AS k " +
      "FROM mine m JOIN rooms r ON r._key = m.room_id WHERE m.involvement IS NOT 'invisible'), " +
      "places AS (SELECT " + Db.json("users", "u") + " AS j, u.created_at AS t, u._key AS k FROM users u " +
      "WHERE u.status = 'active' AND u._key NOT IN (SELECT id FROM excluded) ORDER BY u.created_at, u._key " +
      "LIMIT max(?2 - (SELECT count(*) FROM excluded), 0)) " +
      "SELECT '{\"memberships\":[' || coalesce((SELECT group_concat(j, ',' ORDER BY n, k) FROM list), '') || " +
      "'],\"placeholders\":[' || coalesce((SELECT group_concat(j, ',' ORDER BY t, k) FROM places), '') || ']}' AS v",
      [user_key, Sidebar.DIRECT_PLACEHOLDERS])
    sig = md5(text)
    return {"same": true, "sig": sig} if sig == known

    data = json_parse(text)
    data["same"] = false
    data["sig"] = sig
    data
  end
end
