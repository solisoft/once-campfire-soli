class Ban < Model
  static def banned?(ip_address)
    return false if ip_address.blank?

    ip = ip_address
    rows = @sdbql{ RETURN LENGTH(FOR b IN bans FILTER b.ip_address == #{ip} LIMIT 1 RETURN 1) }
    rows.is_a?("array") && rows[0] > 0
  end

  # Ban#ip_address_is_public: loopback, private and link-local addresses are refused.
  static def public_ip?(ip)
    return false if ip.blank?

    v = ip.downcase
    return false if v == "::1" || v.starts_with("127.") || v.starts_with("10.") || v.starts_with("192.168.")
    return false if v.starts_with("169.254.") || v.starts_with("fe80:") || v.starts_with("fc") || v.starts_with("fd")
    return false if v == "0.0.0.0" || v == "::"

    if v.starts_with("172.")
      second = int(v.split(".")[1]) rescue 0
      return false if second >= 16 && second <= 31
    end
    Regex.matches("^(\\d{1,3}\\.){3}\\d{1,3}$|^[0-9a-f:]+$", v)
  end

  static def create_for(user_key, ip)
    return nil unless Ban.public_ip?(ip)

    now = Clock.now
    Ids.create(Ban, {"user_id": user_key, "ip_address": ip, "created_at": now, "updated_at": now})
  end

  static def delete_for_user(user_key)
    uk = user_key
    @sdbql{ FOR b IN bans FILTER b.user_id == #{uk} REMOVE b IN bans }
  end
end
