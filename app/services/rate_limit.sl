# ActionController::RateLimiting in a fixed window, counted in SQLite: the window starts with
# the first request and lasts within_seconds.
class RateLimit
  static def allow?(key, limit, within_seconds)
    now = Clock.now
    count = Db.value("INSERT INTO rate_limits (name, count, expires_at) VALUES (?, 1, ?) " +
                     "ON CONFLICT (name) DO UPDATE SET count = CASE WHEN expires_at <= ? THEN 1 ELSE count + 1 END, " +
                     "expires_at = CASE WHEN expires_at <= ? THEN excluded.expires_at ELSE expires_at END " +
                     "RETURNING count AS v", [key, now + within_seconds * 1000, now, now])
    count.nil? || count <= limit
  end
end
