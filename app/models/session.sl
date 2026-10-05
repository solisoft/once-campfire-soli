# Sessions live in SoliKV: "campfire:session:<token>" holds the session as JSON, and
# "campfire:user_sessions:<user key>" the set of a user's tokens, for signing a user out
# everywhere (deactivation, bans) and for their IP addresses (bans). No expiry, like the
# reference's sessions table: a session ends when it is destroyed.
class Session
  static ACTIVITY_REFRESH_MS: Int = 3600000

  static def key(token)
    "campfire:session:" + token
  end

  static def user_key_set(user_key)
    "campfire:user_sessions:" + user_key
  end

  static def start(user_key, user_agent, ip_address)
    now = Clock.now
    token = Crypto.random_token(24)
    session = {"_key": token, "token": token, "user_id": user_key, "user_agent": user_agent, "ip_address": ip_address,
               "last_active_at": now, "created_at": now, "updated_at": now}
    KV.set(Session.key(token), json_stringify(session))
    KV.sadd(Session.user_key_set(user_key), token)
    session
  end

  static def find(token)
    return nil if token.blank?

    raw = KV.get(Session.key(token)) rescue nil
    return nil if raw.nil?

    JSON.parse(raw) rescue nil
  end

  # The session and its user (Action Cable connections).
  static def find_with_user(token)
    session = Session.find(token)
    return nil if session.nil?

    user = User.find_hash(session["user_id"])
    user.nil? ? nil : {"session": session, "user": user}
  end

  # The account, and the session and its user when the token names one: every request's
  # first lookup (behind SessionCache). One SoliKV read, then one SoliDB query.
  static def context(token)
    session = Session.find(token)
    uk = session.nil? ? "" : session["user_id"]
    rows = @sdbql{
      LET account = FIRST(FOR a IN accounts FILTER a._key == "campfire" RETURN a)
      LET user = #{uk} == "" ? null : FIRST(FOR u IN users FILTER u._key == #{uk} RETURN u)
      RETURN {account: account, user: user}
    }
    found = Db.first(rows)
    return {"account": nil, "session": nil, "user": nil} if found.nil?

    found["session"] = found["user"].nil? ? nil : session
    found
  end

  static def resume(session, user_agent, ip_address)
    now = Clock.now
    return nil unless session["last_active_at"] < now - Session.ACTIVITY_REFRESH_MS

    session["user_agent"] = user_agent
    session["ip_address"] = ip_address
    session["last_active_at"] = now
    session["updated_at"] = now
    KV.set(Session.key(session["token"]), json_stringify(session)) rescue nil
  end

  static def destroy_token(token)
    session = Session.find(token)
    KV.delete(Session.key(token)) rescue nil
    KV.srem(Session.user_key_set(session["user_id"]), token) rescue nil unless session.nil?
  end

  static def tokens_for_user(user_key)
    tokens = KV.smembers(Session.user_key_set(user_key)) rescue []
    tokens.is_a?("array") ? tokens : []
  end

  static def destroy_for_user(user_key)
    for token in Session.tokens_for_user(user_key)
      KV.delete(Session.key(token)) rescue nil
    end
    KV.delete(Session.user_key_set(user_key)) rescue nil
  end

  static def ip_addresses_for_user(user_key)
    ips = []
    for token in Session.tokens_for_user(user_key)
      session = Session.find(token)
      ip = session.nil? ? nil : session["ip_address"]
      ips.push(ip) unless ip.blank? || ips.include?(ip)
    end
    ips
  end
end
