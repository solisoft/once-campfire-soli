class PushSubscription < Model
  static PERMITTED_ENDPOINT_HOSTS: Array = [
    "jmt17.google.com", "fcm.googleapis.com", "updates.push.services.mozilla.com",
    "web.push.apple.com", "notify.windows.com"
  ]

  static def for_user(user_key)
    Db.rows("SELECT " + Db.json("push_subscriptions", "p") + " AS j FROM push_subscriptions p WHERE p.user_id = ? ORDER BY p.created_at, p._key", [user_key])
  end

  static def find_for_user(user_key, key)
    Db.row("SELECT " + Db.json("push_subscriptions", "p") + " AS j FROM push_subscriptions p WHERE p.user_id = ? AND p._key = ?", [user_key, str(key)])
  end

  static def find_matching(user_key, endpoint, p256dh, auth)
    Db.row("SELECT " + Db.json("push_subscriptions", "p") + " AS j FROM push_subscriptions p WHERE p.user_id = ? AND p.endpoint = ? " +
           "AND p.p256dh_key = ? AND p.auth_key = ? LIMIT 1", [user_key, endpoint, p256dh, auth])
  end

  # Push::Subscription#validate_endpoint_url: https, port 443, a known push service.
  static def endpoint_error(endpoint)
    return "is not a valid URL" if endpoint.blank?

    m = Regex.capture("^(?P<scheme>[a-zA-Z][a-zA-Z0-9+.-]*)://(?P<host>[^/:?#]+)(?::(?P<port>\\d+))?(?:[/?#].*)?$", endpoint)
    return "is not a valid URL" if m.nil?
    return "must use HTTPS" if m["scheme"].downcase != "https"
    return "must use the default HTTPS port" if !m["port"].nil? && m["port"] != "" && m["port"] != "443"

    host = m["host"].downcase
    permitted = PushSubscription.PERMITTED_ENDPOINT_HOSTS.filter { |p| host == p || host.ends_with("." + p) }
    return "is not a permitted push service" if permitted.length == 0

    nil
  end

  static def touch(key)
    Db.update_row("push_subscriptions", key, {"updated_at": Clock.now})
  end

  static def destroy_key(key)
    Db.delete_row("push_subscriptions", key)
  end

  static def destroy_by_endpoint(user_key, endpoint)
    Db.exec("DELETE FROM push_subscriptions WHERE user_id = ? AND endpoint = ?", [user_key, endpoint])
  end

  static def destroy_for_user(user_key)
    Db.exec("DELETE FROM push_subscriptions WHERE user_id = ?", [user_key])
  end

  # @push_subscriptions.create: the subscription, or nil when the endpoint is refused.
  static def create_for(user_key, endpoint, p256dh, auth, user_agent)
    return nil unless PushSubscription.endpoint_error(endpoint).nil?

    now = Clock.now
    Ids.create("push_subscriptions", {"user_id": user_key, "endpoint": endpoint, "p256dh_key": p256dh, "auth_key": auth,
                                  "user_agent": user_agent, "created_at": now, "updated_at": now})
  end

  static def destroy_for(user_key, key)
    Db.exec("DELETE FROM push_subscriptions WHERE user_id = ? AND _key = ?", [user_key, str(key)])
  end

  # The subscription with the badge its notifications carry: user.memberships.unread.count.
  static def with_badge(subscription)
    subscription["badge"] = Db.value("SELECT count(*) AS v FROM memberships WHERE user_id = ? AND unread_at IS NOT NULL",
                                     [subscription["user_id"]])
    subscription
  end
end
