# WebPush::Notification#deliver with Soli's native VAPID support. Endpoints are checked again
# at delivery (Push::Subscription#resolved_endpoint_ip); dead subscriptions are removed.
class WebPush
  static def configured?
    !(getenv("VAPID_PUBLIC_KEY") ?? "").blank? && !(getenv("VAPID_PRIVATE_KEY") ?? "").blank?
  end

  static def deliver(subscription, payload)
    return nil unless WebPush.configured?
    return nil unless PushSubscription.endpoint_error(subscription["endpoint"]).nil?

    message = json_stringify({"title": payload["title"], "options": {
      "body": payload["body"], "icon": "/account/logo",
      "data": {"path": payload["path"], "badge": subscription["badge"] ?? 0}
    }})
    target = {"endpoint": subscription["endpoint"], "keys": {"p256dh": subscription["p256dh_key"], "auth": subscription["auth_key"]}}
    result = vapid_send(target, message, getenv("VAPID_PRIVATE_KEY"), getenv("VAPID_PUBLIC_KEY"),
                        getenv("VAPID_SUBJECT") ?? "mailto:support@37signals.com", {"urgency": "high"}) rescue nil
    return nil if result.nil?

    PushSubscription.destroy_key(subscription["_key"]) if result["status"] == 404 || result["status"] == 410
    result
  end
end
