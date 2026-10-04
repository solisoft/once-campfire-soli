# searches#index in one round trip: the matching messages the user can reach (the last 100,
# every term matching as FTS5 would), their recent searches, and the room to return to.
class SearchPage
  static def load(user_key, query, last_room_key)
    terms = Stemmer.query_terms(query ?? "")
    uk = user_key
    first = terms.length > 0 ? terms[0] : ""
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
          RETURN m
      )
      LET recent = (FOR s IN searches FILTER s.user_id == #{uk} SORT s.updated_at DESC, s._key DESC RETURN s)
      LET last = #{last_room} IN room_ids ? #{last_room} : FIRST(
        FOR r IN rooms FILTER r._key IN room_ids SORT r.created_at, r._key LIMIT 1 RETURN r._key
      )
      RETURN {messages: found, recent: recent, return_to_room: last}
    }
    return {"messages": [], "recent": [], "return_to_room": nil} unless rows.is_a?("array") && rows.length > 0

    rows[0]
  end
end
