class Webhook < Model
  static ENDPOINT_TIMEOUT_SECONDS: Int = 7

  static def for_user(user_key)
    return nil if user_key.nil?

    uk = user_key
    rows = @sdbql{ FOR w IN webhooks FILTER w.user_id == #{uk} LIMIT 1 RETURN w }
    rows.is_a?("array") && rows.length > 0 ? rows[0] : nil
  end

  # User::Bot#update_webhook_url!
  static def set_url(user_key, url)
    existing = Webhook.for_user(user_key)
    now = Clock.now
    if url.blank?
      Webhook.delete_for_user(user_key) unless existing.nil?
    elsif existing.nil?
      Ids.create(Webhook, {"user_id": user_key, "url": url, "created_at": now, "updated_at": now})
    else
      Webhook.update(existing["_key"], {"url": url, "updated_at": now})
    end
  end

  static def delete_for_user(user_key)
    uk = user_key
    @sdbql{ FOR w IN webhooks FILTER w.user_id == #{uk} REMOVE w IN webhooks }
  end
end
