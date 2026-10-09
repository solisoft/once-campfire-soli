# searches#index in one query: the matching messages the user can reach (the last 100, every
# word matching in the FTS5 porter index, as in the reference), their recent searches, and the
# room to return to.
class SearchPage
  static def load(user_key, query, last_room_key)
    terms = Message.search_query(query ?? "")
    name = "search_html:" + user_key + ":" + terms
    cached = PageCache.get(name)
    known = cached.nil? ? "" : cached["sig"]
    found = terms == "" ? "SELECT NULL AS k, NULL AS s, NULL AS t, NULL AS ok WHERE 0" :
      "SELECT m._key AS k, m.html_key AS s, m.created_at AS t, m.html_key IS ?3 || m.updated_at AS ok " +
      "FROM message_search_index idx JOIN messages m ON m._key = CAST(idx.rowid AS TEXT) " +
      "WHERE idx.body MATCH ?2 AND m.room_id IN (SELECT room_id FROM reachable) ORDER BY m.created_at DESC, m._key DESC LIMIT 100"
    page = Db.row("WITH reachable AS (SELECT room_id FROM memberships WHERE user_id = ?1), found AS MATERIALIZED (" + found + "), " +
      "facts AS (SELECT 'v:' || coalesce((SELECT group_concat(s, ',' ORDER BY t, k) FROM found), '') AS sig, " +
      "NOT EXISTS (SELECT 1 FROM found WHERE NOT ok) AS fresh) " +
      "SELECT json_object('keys', json((SELECT json_group_array(k ORDER BY t, k) FROM found)), 'sig', f.sig, " +
      "'same', json(CASE WHEN f.fresh AND f.sig = ?4 THEN 'true' ELSE 'false' END), " +
      "'html', CASE WHEN f.fresh AND f.sig != ?4 THEN coalesce((SELECT group_concat(m.html, char(10) ORDER BY p.t, p.k) FROM found p JOIN messages m ON m._key = p.k), '') END, " +
      "'recent', json((SELECT json_group_array(" + Db.json("searches", "s") + " ORDER BY s.updated_at DESC, s._key DESC) " +
      "FROM searches s WHERE s.user_id = ?1)), " +
      "'return_to_room', CASE WHEN ?5 IN (SELECT room_id FROM reachable) THEN ?5 ELSE (SELECT r._key FROM rooms r " +
      "WHERE r._key IN (SELECT room_id FROM reachable) ORDER BY r.created_at, r._key LIMIT 1) END) AS j FROM facts f",
      [user_key, terms, MessagePresenter.VERSION + ":", known, last_room_key ?? ""])
    return {"keys": [], "html": "", "recent": [], "return_to_room": nil} if page.nil?

    if page["same"]
      page["html"] = cached["html"]
    elsif !page["html"].nil?
      PageCache.set(name, {"sig": page["sig"], "html": page["html"]})
    end
    page
  end
end
