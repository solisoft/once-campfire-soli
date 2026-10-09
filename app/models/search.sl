class Search < Model
  # Search.record: find_or_create_by(query).touch, then keep the ten most recent.
  static def record(user_key, query)
    now = Clock.now
    k = Db.value("SELECT _key AS v FROM searches WHERE user_id = ? AND query = ?", [user_key, query])
    if k.nil?
      Ids.create("searches", {"user_id": user_key, "query": query, "created_at": now, "updated_at": now})
      Db.exec("DELETE FROM searches WHERE user_id = ? AND _key NOT IN (SELECT _key FROM searches WHERE user_id = ? " +
              "ORDER BY updated_at DESC, _key DESC LIMIT 10)", [user_key, user_key])
    else
      Db.exec("UPDATE searches SET updated_at = ? WHERE _key = ?", [now, k])
    end
  end

  static def recent_for(user_key)
    Db.rows("SELECT " + Db.json("searches", "s") + " AS j FROM searches s WHERE s.user_id = ? " +
            "ORDER BY s.updated_at DESC, s._key DESC", [user_key])
  end

  static def clear_for(user_key)
    Db.exec("DELETE FROM searches WHERE user_id = ?", [user_key])
  end
end
