# The reference's sessions table: a session ends when it is destroyed (no expiry). The
# account, the session and its user come back together, in one query, for every request
# (behind SessionCache).
class Session
  static ACTIVITY_REFRESH_MS: Int = 3600000

  static def json(alias_name)
    "json_object('_key', " + alias_name + ".token, " + Db.fields("sessions", alias_name) + ")"
  end

  static def start(user_key, user_agent, ip_address)
    now = Clock.now
    token = Crypto.random_token(24)
    session = {"token": token, "user_id": user_key, "user_agent": user_agent, "ip_address": ip_address,
               "last_active_at": now, "created_at": now, "updated_at": now}
    Db.insert("sessions", session)
    session["_key"] = token
    session
  end

  static def find(token)
    return nil if token.blank?

    Db.row("SELECT " + Session.json("s") + " AS j FROM sessions s WHERE s.token = ?", [token])
  end

  # The session and its user (Action Cable connections).
  static def find_with_user(token)
    return nil if token.blank?

    Db.row("SELECT json_object('session', " + Session.json("s") + ", 'user', " + Db.json("users", "u") + ") AS j " +
           "FROM sessions s JOIN users u ON u._key = s.user_id WHERE s.token = ?", [token])
  end

  # The account, and the session and its user when the token names one: every request's
  # first lookup (behind SessionCache).
  static def context(token)
    found = Db.row("SELECT json_object('account', json((SELECT " + Db.json("accounts", "a") + " FROM accounts a WHERE a._key = 'campfire')), " +
                   "'session', CASE WHEN u._key IS NULL THEN NULL ELSE " + Session.json("s") + " END, " +
                   "'user', CASE WHEN u._key IS NULL THEN NULL ELSE " + Db.json("users", "u") + " END) AS j " +
                   "FROM (SELECT 1) LEFT JOIN sessions s ON s.token = ? LEFT JOIN users u ON u._key = s.user_id",
                   [token ?? ""])
    found ?? {"account": nil, "session": nil, "user": nil}
  end

  static def resume(session, user_agent, ip_address)
    now = Clock.now
    return nil unless session["last_active_at"] < now - Session.ACTIVITY_REFRESH_MS

    session["user_agent"] = user_agent
    session["ip_address"] = ip_address
    session["last_active_at"] = now
    session["updated_at"] = now
    Db.exec("UPDATE sessions SET user_agent = ?, ip_address = ?, last_active_at = ?, updated_at = ? WHERE token = ?",
            [user_agent, ip_address, now, now, session["token"]])
  end

  static def destroy_token(token)
    Db.exec("DELETE FROM sessions WHERE token = ?", [token ?? ""])
  end

  static def destroy_for_user(user_key)
    Db.exec("DELETE FROM sessions WHERE user_id = ?", [user_key])
  end

  static def ip_addresses_for_user(user_key)
    Db.rows("SELECT json_quote(ip_address) AS j FROM sessions WHERE user_id = ? AND ip_address IS NOT NULL " +
            "AND ip_address != '' GROUP BY ip_address ORDER BY min(created_at)", [user_key])
  end
end
