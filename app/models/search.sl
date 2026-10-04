class Search < Model
  # Search.record: find_or_create_by(query).touch, then keep the ten most recent.
  static def record(user_key, query)
    uk = user_key
    q = query
    now = Clock.now
    rows = @sdbql{ FOR s IN searches FILTER s.user_id == #{uk} AND s.query == #{q} LIMIT 1 RETURN s._key }
    if rows.is_a?("array") && rows.length > 0
      k = rows[0]
      @sdbql{ FOR s IN searches FILTER s._key == #{k} UPDATE s WITH {updated_at: #{now}} IN searches }
    else
      Ids.create(Search, {"user_id": uk, "query": q, "created_at": now, "updated_at": now})
      @sdbql{
        LET keep = (FOR s IN searches FILTER s.user_id == #{uk} SORT s.updated_at DESC, s._key DESC LIMIT 10 RETURN s._key)
        FOR s IN searches FILTER s.user_id == #{uk} AND s._key NOT IN keep
          REMOVE s IN searches
      }
    end
  end

  static def recent_for(user_key)
    uk = user_key
    rows = @sdbql{ FOR s IN searches FILTER s.user_id == #{uk} SORT s.updated_at DESC, s._key DESC RETURN s }
    rows.is_a?("array") ? rows : []
  end

  static def clear_for(user_key)
    uk = user_key
    @sdbql{ FOR s IN searches FILTER s.user_id == #{uk} REMOVE s IN searches }
  end
end
