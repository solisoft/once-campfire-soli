# Sessions kept in memory: each worker remembers the account, session and user a token
# resolved to for SESSION_CACHE_TTL_MS (default 2000; 0 disables), so most requests
# authenticate without a query.
#
# The cost is that a change made elsewhere (a sign-out, ban or deactivation in another
# worker, a role or account edit) reaches this worker within the TTL rather than at once.
# The worker that handles a sign-out forgets the session immediately.
class SessionCache
  static def ttl
    raw = getenv("SESSION_CACHE_TTL_MS") ?? "2000"
    int(raw) rescue 2000
  end

  static def fetch(token)
    return Session.context(token) if token.nil? || SessionCache.ttl == 0

    now = Clock.now
    name = "session:" + token
    cached = PageCache.get(name)
    return cached["context"] if !cached.nil? && cached["expires_at"] > now

    context = Session.context(token)
    PageCache.set(name, {"context": context, "expires_at": now + SessionCache.ttl}) unless context["user"].nil?
    context
  end

  static def forget(token)
    PageCache.set("session:" + token, nil) unless token.nil?
  end
end
