class Session < Model
  static ACTIVITY_REFRESH_MS: Int = 3600000

  static def start(user_key, user_agent, ip_address)
    now = Clock.now
    token = Crypto.random_token(24)
    Ids.create(Session, {"token": token, "user_id": user_key, "user_agent": user_agent, "ip_address": ip_address,
                    "last_active_at": now, "created_at": now, "updated_at": now})
    {"token": token, "user_id": user_key, "last_active_at": now}
  end

  # The session and its user in one round trip.
  static def find_with_user(token)
    return nil if token.blank?

    t = token
    rows = @sdbql{
      FOR s IN sessions FILTER s.token == #{t}
        FOR u IN users FILTER u._key == s.user_id
          LIMIT 1
          RETURN {session: s, user: u}
    }
    Db.first(rows)
  end

  # The account, and the session and its user when the token names one: every request's
  # first (and for most pages only) lookup.
  static def context(token)
    t = token ?? ""
    rows = @sdbql{
      LET account = FIRST(FOR a IN accounts FILTER a._key == "campfire" RETURN a)
      LET session = #{t} == "" ? null : FIRST(FOR s IN sessions FILTER s.token == #{t} LIMIT 1 RETURN s)
      LET user = session == null ? null : FIRST(FOR u IN users FILTER u._key == session.user_id RETURN u)
      RETURN {account: account, session: session, user: user}
    }
    Db.array(rows).length > 0 ? rows[0] : {"account": nil, "session": nil, "user": nil}
  end

  static def resume(session, user_agent, ip_address)
    now = Clock.now
    return nil unless session["last_active_at"] < now - Session.ACTIVITY_REFRESH_MS

    k = session["_key"]
    @sdbql{
      FOR s IN sessions FILTER s._key == #{k}
        UPDATE s WITH {user_agent: #{user_agent}, ip_address: #{ip_address}, last_active_at: #{now}, updated_at: #{now}} IN sessions
    }
  end

  static def destroy_token(token)
    t = token
    @sdbql{ FOR s IN sessions FILTER s.token == #{t} REMOVE s IN sessions }
  end

  static def destroy_for_user(user_key)
    uk = user_key
    @sdbql{ FOR s IN sessions FILTER s.user_id == #{uk} REMOVE s IN sessions }
  end

  static def ip_addresses_for_user(user_key)
    uk = user_key
    rows = @sdbql{ FOR s IN sessions FILTER s.user_id == #{uk} AND s.ip_address != null AND s.ip_address != "" RETURN DISTINCT s.ip_address }
    Db.array(rows)
  end
end
