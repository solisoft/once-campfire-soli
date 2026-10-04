# User::Bot webhooks (MessagesController#deliver_webhooks_to_bots and Webhook#deliver).
#
# A message wakes the room's active bots in a direct room, else the active bots it mentions,
# never its own author, and only bots with a webhook. Each delivery is a BotWebhookJob: it
# POSTs the payload and turns a text/plain or text/html answer into a message from the bot,
# any other content type into an attachment.
#
# Unlike the reference, Soli's HTTP client refuses loopback and private addresses: a bot
# served from the internal network needs its host in SOLI_HTTP_ALLOW_HOSTS.
class Bots
  static ENDPOINT_TIMEOUT_SECONDS: Int = 7
  static MIME_EXTENSIONS: Hash = {
    "application/json": "json", "application/pdf": "pdf", "application/xml": "xml", "text/xml": "xml",
    "application/zip": "zip", "application/gzip": "gzip", "text/csv": "csv", "text/css": "css",
    "text/javascript": "js", "application/javascript": "js", "text/calendar": "ics", "text/vcard": "vcf",
    "application/rss+xml": "rss", "application/atom+xml": "atom", "application/x-yaml": "yaml",
    "image/png": "png", "image/jpeg": "jpeg", "image/gif": "gif", "image/bmp": "bmp", "image/tiff": "tiff",
    "image/svg+xml": "svg", "image/webp": "webp", "audio/mpeg": "mp3", "audio/ogg": "ogg",
    "audio/aac": "m4a", "audio/webm": "webm", "video/mp4": "mp4", "video/webm": "webm", "video/ogg": "ogv"
  }

  # Cheap when nothing is due: a shared room's message without mentions costs no query.
  static def deliver_webhooks(room, message, author_key, base_url = nil)
    bot_keys = []
    if Room.direct?(room)
      bot_keys = Bots.direct_room_bots(room["_key"], author_key)
    else
      body = message["body"] ?? ""
      return nil unless body.contains(RichText.MENTION_TYPE)

      mentioned = RichText.mentioned_user_keys(body).filter { |k| k != author_key }
      bot_keys = Bots.mentioned_bots(room["_key"], mentioned) if mentioned.length > 0
    end
    return nil if bot_keys.length == 0

    base = base_url ?? (RoomPage.base_url(req) rescue nil)
    for bot_key in bot_keys
      BotWebhookJob.perform_later({"bot_id": bot_key, "message_id": message["_key"], "base_url": base}, {"max_retries": 2})
    end
  end

  # @room.users.active_bots, with a webhook, but the author.
  static def direct_room_bots(room_key, author_key)
    rk = room_key
    ak = author_key
    rows = @sdbql{
      FOR w IN webhooks FILTER w.user_id != #{ak}
        FOR m IN memberships FILTER m.room_id == #{rk} AND m.user_id == w.user_id
          FOR u IN users FILTER u._key == m.user_id AND u.role == "bot" AND u.status == "active"
            RETURN DISTINCT u._key
    }
    Db.array(rows)
  end

  # @message.mentionees.active_bots: mentioned members of the room, with a webhook.
  static def mentioned_bots(room_key, user_keys)
    rk = room_key
    rows = @sdbql{
      FOR k IN #{user_keys}
        FOR w IN webhooks FILTER w.user_id == k
          FOR m IN memberships FILTER m.room_id == #{rk} AND m.user_id == k
            FOR u IN users FILTER u._key == k AND u.role == "bot" AND u.status == "active"
              RETURN DISTINCT k
    }
    Db.array(rows)
  end

  # Webhook#deliver
  static def deliver(bot, message, base_url)
    webhook = Webhook.for_user(bot["_key"])
    return nil if webhook.nil? || webhook["url"].blank?

    room = Room.find_hash(message["room_id"])
    creator = User.find_hash(message["creator_id"])
    return nil if room.nil? || creator.nil?

    response = nil
    try
      response = HTTP.request("POST", webhook["url"], {"Content-Type": "application/json", "timeout": Bots.ENDPOINT_TIMEOUT_SECONDS},
        json_stringify(Bots.payload(bot, message, room, creator)))
    catch error
      reason = str(error)
      if Regex.matches("(?i)time(d)? ?out", reason)
        Bots.reply(bot, room["_key"], "Failed to respond within " + str(Bots.ENDPOINT_TIMEOUT_SECONDS) + " seconds", nil, base_url)
      else
        print("[bots] webhook for bot " + bot["_key"] + " failed: " + reason)
      end
      return nil
    end

    content_type = Bots.content_type(response)
    body = response["body"] ?? ""
    if response["status"] == 200 && (content_type == "text/plain" || content_type == "text/html")
      Bots.reply(bot, room["_key"], body, nil, base_url)
    elsif !content_type.blank?
      extension = Bots.MIME_EXTENSIONS[content_type] ?? ""
      attachment = Attachments.create_message_attachment({
        "data": Base64.encode(body), "filename": "attachment." + extension, "content_type": content_type, "size": body.length
      })
      Bots.reply(bot, room["_key"], nil, attachment, base_url)
    end
  end

  # Webhook#payload
  static def payload(bot, message, room, creator)
    rk = room["_key"]
    {
      "user": {"id": BotApi.id(creator["_key"]), "name": creator["name"]},
      "room": {"id": BotApi.id(rk), "name": room["name"], "path": "/rooms/" + rk + "/" + User.bot_key(bot) + "/messages"},
      "message": {
        "id": BotApi.id(message["_key"]),
        "body": {"html": message["body"], "plain": Bots.without_recipient_mentions(message["plain_text"] ?? "", bot)},
        "path": "/rooms/" + rk + "/@" + message["_key"]
      }
    }
  end

  static def without_recipient_mentions(plain, bot)
    Regex.replace_all("^[\\p{Z}\\s]+|[\\p{Z}\\s]+$", plain.replace("@" + bot["name"], ""), "")
  end

  # The response's media type, without parameters.
  static def content_type(response)
    value = nil
    (response["headers"] ?? {}).each do |k, v|
      value = v if k.downcase == "content-type"
    end
    return nil if value.nil?

    str(value).split(";")[0].trim.downcase
  end

  # room.messages.create!(creator: bot).broadcast_create
  static def reply(bot, room_key, body, attachment, base_url)
    found = Membership.with_room_and_members(bot["_key"], room_key)
    return nil if found.nil?

    created = Message.create_message(found["room"], bot, body, attachment, nil, base_url ?? "", found["members"])
    Broadcasts.message_created(found["room"], created["members"], created["message"]["html"])
  end
end
