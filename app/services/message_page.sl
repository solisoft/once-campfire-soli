# messages#index: a page of messages before or after one (or the last page), as HTML.
# Like RoomPage, SQLite joins the cached message HTML and the worker keeps the last answer
# for each page under its signature, so a repeated page costs a signature check.
class MessagePage
  # nil when the anchor is not a message of the room; else {html, count}.
  static def load(room_key, before_key, after_key, base_url)
    rk = str(room_key)
    mode = before_key.blank? ? (after_key.blank? ? "last" : "after") : "before"
    anchor = str(before_key.blank? ? (after_key ?? "") : before_key)
    name = "messages:" + rk + ":" + mode + ":" + anchor
    cached = PageCache.get(name)
    known = cached.nil? ? "" : cached["sig"]
    window = mode == "after" ?
      "m.created_at > (SELECT t FROM anchor) ORDER BY m.created_at, m._key" :
      (mode == "last" ? "1 ORDER BY m.created_at DESC, m._key DESC" : "m.created_at < (SELECT t FROM anchor) ORDER BY m.created_at DESC, m._key DESC")
    page = Db.row("WITH anchor AS (SELECT created_at AS t FROM messages WHERE _key = ?2 AND room_id = ?1), " +
      "page AS MATERIALIZED (SELECT m._key AS k, m.html_key AS s, m.created_at AS t, m.html_key IS ?3 || m.updated_at AS ok " +
      "FROM messages m WHERE m.room_id = ?1 AND " + window + " LIMIT 40), " +
      "facts AS (SELECT 'v:' || coalesce((SELECT group_concat(s, ',' ORDER BY t, k) FROM page), '') AS sig, " +
      "NOT EXISTS (SELECT 1 FROM page WHERE NOT ok) AS fresh) " +
      "SELECT json_object('found', json(CASE WHEN ?5 OR EXISTS (SELECT 1 FROM anchor) THEN 'true' ELSE 'false' END), " +
      "'keys', json((SELECT json_group_array(k ORDER BY t, k) FROM page)), 'sig', f.sig, " +
      "'same', json(CASE WHEN f.fresh AND f.sig = ?4 THEN 'true' ELSE 'false' END), " +
      "'html', CASE WHEN f.fresh AND f.sig != ?4 THEN coalesce((SELECT group_concat(m.html, char(10) ORDER BY p.t, p.k) FROM page p JOIN messages m ON m._key = p.k), '') END) " +
      "AS j FROM facts f", [rk, anchor, MessagePresenter.VERSION + ":", known, mode == "last"])
    return nil if page.nil? || !page["found"]

    return {"html": cached["html"], "count": page["keys"].length} if page["same"]

    html = page["html"]
    if html.nil?
      html = MessagePresenter.join(Message.find_many_ordered(page["keys"]), base_url)
    else
      PageCache.set(name, {"sig": page["sig"], "html": html})
    end
    {"html": html, "count": page["keys"].length}
  end
end
