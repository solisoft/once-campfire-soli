# ActionController::RateLimiting in a fixed window, counted in SoliKV when it is up.
class RateLimit
  static def allow?(key, limit, within_seconds)
    count = Cache.increment("rate_limit:" + key) rescue nil
    return true if count.nil?

    Cache.expire("rate_limit:" + key, within_seconds) rescue nil if count == 1
    count <= limit
  end
end
