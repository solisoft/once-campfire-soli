# ActionController::RateLimiting in a fixed window, counted in SoliKV.
class RateLimit
  static def allow?(key, limit, within_seconds)
    name = "campfire:rate_limit:" + key
    count = KV.incr(name) rescue nil
    return true if count.nil?

    KV.expire(name, within_seconds) rescue nil if count == 1
    count <= limit
  end
end
