class Webhook < Model
  static ENDPOINT_TIMEOUT_SECONDS: Int = 7

  static def for_user(user_key)
    return nil if user_key.nil?

    Db.row("SELECT " + Db.json("webhooks", "w") + " AS j FROM webhooks w WHERE w.user_id = ? LIMIT 1", [user_key])
  end

  # User::Bot#update_webhook_url!
  static def set_url(user_key, url)
    existing = Webhook.for_user(user_key)
    now = Clock.now
    if url.blank?
      Webhook.delete_for_user(user_key) unless existing.nil?
    elsif existing.nil?
      Ids.create("webhooks", {"user_id": user_key, "url": url, "created_at": now, "updated_at": now})
    else
      Db.update_row("webhooks", existing["_key"], {"url": url, "updated_at": now})
    end
  end

  static def delete_for_user(user_key)
    Db.exec("DELETE FROM webhooks WHERE user_id = ?", [user_key])
  end
end
