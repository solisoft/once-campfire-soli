class PushSubscription < Model
  static PERMITTED_ENDPOINT_HOSTS: Array = [
    "jmt17.google.com", "fcm.googleapis.com", "updates.push.services.mozilla.com",
    "web.push.apple.com", "notify.windows.com"
  ]

  static def for_user(user_key)
    uk = user_key
    rows = @sdbql{ FOR p IN push_subscriptions FILTER p.user_id == #{uk} SORT p.created_at, p._key RETURN p }
    Db.array(rows)
  end

  static def find_for_user(user_key, key)
    uk = user_key
    k = str(key)
    rows = @sdbql{ FOR p IN push_subscriptions FILTER p.user_id == #{uk} AND p._key == #{k} LIMIT 1 RETURN p }
    Db.first(rows)
  end

  static def find_matching(user_key, endpoint, p256dh, auth)
    uk = user_key
    rows = @sdbql{
      FOR p IN push_subscriptions
        FILTER p.user_id == #{uk} AND p.endpoint == #{endpoint} AND p.p256dh_key == #{p256dh} AND p.auth_key == #{auth}
        LIMIT 1
        RETURN p
    }
    Db.first(rows)
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
    k = key
    now = Clock.now
    @sdbql{ FOR p IN push_subscriptions FILTER p._key == #{k} UPDATE p WITH {updated_at: #{now}} IN push_subscriptions }
  end

  static def destroy_key(key)
    k = key
    @sdbql{ FOR p IN push_subscriptions FILTER p._key == #{k} REMOVE p IN push_subscriptions }
  end

  static def destroy_by_endpoint(user_key, endpoint)
    uk = user_key
    @sdbql{ FOR p IN push_subscriptions FILTER p.user_id == #{uk} AND p.endpoint == #{endpoint} REMOVE p IN push_subscriptions }
  end

  static def destroy_for_user(user_key)
    uk = user_key
    @sdbql{ FOR p IN push_subscriptions FILTER p.user_id == #{uk} REMOVE p IN push_subscriptions }
  end
end
