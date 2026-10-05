# The reference's Authentication, AllowBrowser and BlockBannedRequests concerns, run as the
# base controller's first hook. It leaves on the request:
#
#   req["current_user"]      the signed-in user (or the bot of a bot_key route), or nil
#   req["current_session"]   the session row
#   req["authenticated_by"]  "session", "bot_key" or ""
#   req["account"]           the account, or nil before first run
class Authentication
  static COOKIE: String = "session_token"
  static TWENTY_YEARS: Int = 631152000

  # Routes that skip require_authentication (allow_unauthenticated_access).
  static PUBLIC_PATTERNS: Array = [
    "^/first_run$", "^/session/new$", "^/session/transfers/[^/]+$", "^/qr_code/[^/]+$",
    "^/account/logo$", "^/attachments/[^/]+/[^/]+$", "^/webmanifest(\\.json)?$", "^/service-worker(\\.js)?$", "^/up$"
  ]
  # require_unauthenticated_access: signed-in users are sent home.
  static UNAUTHENTICATED_PATTERNS: Array = ["^/join/[^/]+$"]
  # allow_bot_access: the bot_key routes.
  static BOT_PATTERN: String = "^/rooms/[^/]+/[^/]+-[A-Za-z0-9]+/messages"

  static def run(req)
    path = req["path"]
    method = req["method"]
    context = SessionCache.fetch(Authentication.token_from_cookie(cookies[Authentication.COOKIE]))
    req["account"] = context["account"]
    req["authenticated_by"] = ""
    req["_auth_context"] = context

    halt(429, "") if method != "GET" && method != "HEAD" && Ban.banned?(Authentication.remote_ip(req))

    if Authentication.matches_any(path, Authentication.UNAUTHENTICATED_PATTERNS)
      return redirect("/") unless Authentication.restore(req).nil?

      return req
    end

    public_route = Authentication.matches_any(path, Authentication.PUBLIC_PATTERNS) ||
      (path == "/session" && method == "POST")
    if public_route
      Authentication.restore(req)
      return req
    end

    unless Authentication.restore(req).nil?
      return req
    end

    if Regex.matches(Authentication.BOT_PATTERN, path)
      bot_key = path.split("/")[3]
      bot = User.authenticate_bot(url_decode(bot_key) rescue bot_key)
      unless bot.nil?
        req["current_user"] = bot
        req["authenticated_by"] = "bot_key"
        return req
      end
    end

    session_set("return_to_after_authenticating", path + Authentication.query_suffix(req)) if method == "GET"
    redirect("/session/new")
  end

  # restore_authentication: the session named by the signed cookie, resumed.
  static def restore(req)
    found = req["_auth_context"]
    return nil if found.nil? || found["user"].nil?

    Session.resume(found["session"], req["headers"]["user-agent"], Authentication.remote_ip(req))
    req["current_user"] = found["user"]
    req["current_session"] = found["session"]
    req["authenticated_by"] = "session"
    found["user"]
  end

  static def start_session_for(req, user)
    session = Session.start(user["_key"], req["headers"]["user-agent"], Authentication.remote_ip(req))
    set_cookie(Authentication.COOKIE, Signer.generate(session["token"], "session_token"), {
      "http_only": true, "same_site": "Lax", "max_age": Authentication.TWENTY_YEARS,
      "secure": getenv("DISABLE_SSL").blank?
    })
    req["current_user"] = user
    req["authenticated_by"] = "session"
    session
  end

  static def terminate_session(req)
    session = req["current_session"]
    unless session.nil?
      Session.destroy_token(session["token"])
      SessionCache.forget(session["token"])
    end
    set_cookie(Authentication.COOKIE, "", {"max_age": 0, "http_only": true, "same_site": "Lax"})
    Cable.disconnect_user(req["current_user"]["_key"], true) unless req["current_user"].nil?
  end

  # cookies.signed[:session_token]
  static def token_from_cookie(value)
    return nil if value.blank?

    Signer.verify(url_decode(value) rescue value, "session_token")
  end

  # The user behind a raw Cookie header (Action Cable connections).
  static def user_from_cookie_header(header)
    return nil if header.blank?

    for part in header.split(";")
      pair = part.trim.split("=")
      if pair.length >= 2 && pair[0] == Authentication.COOKIE
        token = Authentication.token_from_cookie(pair.drop(1).join("="))
        return nil if token.nil?

        found = Session.find_with_user(token)
        return found.nil? ? nil : found["user"]
      end
    end
    nil
  end

  static def post_authenticating_url
    url = session_get("return_to_after_authenticating")
    session_delete("return_to_after_authenticating")
    url.blank? ? "/" : url
  end

  static def remote_ip(req)
    forwarded = req["headers"]["x-forwarded-for"]
    return forwarded.split(",")[0].trim if !forwarded.blank? && getenv("SOLI_TRUST_PROXY") == "1"

    req["remote_addr"]
  end

  static def query_suffix(req)
    q = req["query"]
    return "" if q.nil? || q.keys.length == 0

    "?" + q.keys.map { |k| url_encode(k) + "=" + url_encode(str(q[k])) }.join("&")
  end

  static def matches_any(path, patterns)
    for pattern in patterns
      return true if Regex.matches(pattern, path)
    end
    false
  end
end
