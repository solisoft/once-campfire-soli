# searches#index in one round trip: the matching messages the user can reach (the last 100,
# every term matching as FTS5 would), their recent searches, and the room to return to.
class SearchPage
  static def load(user_key, query, last_room_key)
    terms = Stemmer.query_terms(query ?? "")
    uk = user_key
    first = terms.length > 0 ? terms[0] : ""
    version = MessagePresenter.VERSION + ":"
    name = "search_html:" + user_key + ":" + terms.join(" ")
    cached = PageCache.get(name)
    known = cached.nil? ? "" : cached["sig"]
    last_room = last_room_key ?? ""
    rows = @sdbql{
      LET room_ids = (FOR s IN memberships FILTER s.user_id == #{uk} RETURN s.room_id)
      LET found = LENGTH(#{terms}) == 0 ? [] : REVERSE(
        FOR h IN (FULLTEXT("messages", "search_text", #{first}))
          LET m = h.doc
          FILTER m.room_id IN room_ids
          LET padded = CONCAT(" ", m.search_text, " ")
          FILTER LENGTH(FOR t IN #{terms} FILTER !CONTAINS(padded, CONCAT(" ", t, " ")) RETURN 1) == 0
          SORT m.created_at DESC, m._key DESC
          LIMIT 100
          RETURN {k: m._key, s: m.html_key, html: m.html_key == CONCAT(#{version}, m.updated_at) ? m.html : null}
      )
      LET stale = (FOR p IN found FILTER p.html == null RETURN p.k)
      LET recent = (FOR s IN searches FILTER s.user_id == #{uk} SORT s.updated_at DESC, s._key DESC RETURN s)
      LET last = #{last_room} IN room_ids ? #{last_room} : FIRST(
        FOR r IN rooms FILTER r._key IN room_ids SORT r.created_at, r._key LIMIT 1 RETURN r._key
      )
      LET sig = MD5(CONCAT_SEPARATOR(",", found[*].s))
      LET fresh = LENGTH(stale) == 0
      RETURN {keys: found[*].k, sig: sig, same: fresh AND sig == #{known},
              html: fresh AND sig != #{known} ? CONCAT_SEPARATOR("\n", found[*].html) : null,
              recent: recent, return_to_room: last}
    }
    return {"keys": [], "html": "", "recent": [], "return_to_room": nil} unless Db.array(rows).length > 0

    page = rows[0]
    if page["same"]
      page["html"] = cached["html"]
    elsif !page["html"].nil?
      PageCache.set(name, {"sig": page["sig"], "html": page["html"]})
    end
    page
  end
end
