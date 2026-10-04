# messages#index: a page of messages before or after one (or the last page), as HTML.
# Like RoomPage, SoliDB joins the cached message HTML and the worker keeps the last answer
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
    version = MessagePresenter.VERSION + ":"
    rows = @sdbql{
      LET at = #{mode} == "last" ? null : FIRST(FOR m IN messages FILTER m._key == #{anchor} AND m.room_id == #{rk} RETURN m.created_at)
      LET page = #{mode} == "after" ? (
        FOR m IN messages FILTER m.room_id == #{rk} AND m.created_at > at
          SORT m.created_at, m._key
          LIMIT 40
          RETURN {k: m._key, s: m.html_key, html: m.html_key == CONCAT(#{version}, m.updated_at) ? m.html : null}
      ) : REVERSE(
        FOR m IN messages FILTER m.room_id == #{rk} AND (#{mode} == "last" OR m.created_at < at)
          SORT m.created_at DESC, m._key DESC
          LIMIT 40
          RETURN {k: m._key, s: m.html_key, html: m.html_key == CONCAT(#{version}, m.updated_at) ? m.html : null}
      )
      LET stale = (FOR p IN page FILTER p.html == null RETURN p.k)
      LET sig = MD5(CONCAT_SEPARATOR(",", page[*].s))
      LET fresh = LENGTH(stale) == 0
      RETURN {found: #{mode} == "last" OR at != null, keys: page[*].k, sig: sig, same: fresh AND sig == #{known},
              html: fresh AND sig != #{known} ? CONCAT_SEPARATOR("\n", page[*].html) : null}
    }
    return nil unless Db.array(rows).length > 0 && rows[0]["found"]

    page = rows[0]
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
