# The bot API's JSON: messages/_message.json.jbuilder, users/_user.json.jbuilder and
# messages/boosts/_boost.json.jbuilder. Ids are numbers, as Rails' integer ids are.
class BotApi
  static def user(user, base_url)
    return nil if user.nil?

    presented = Present.user(user)
    {"id": BotApi.id(user["_key"]), "name": user["name"], "role": user["role"], "avatar_url": base_url + presented["avatar_path"]}
  end

  static def message(message, base_url, creators = nil)
    creator = creators.nil? ? User.find_hash(message["creator_id"]) : creators[message["creator_id"]]
    {
      "id": BotApi.id(message["_key"]),
      "created_at": BotApi.time(message["created_at"]),
      "body": {
        "plain_text": message["plain_text"] ?? "",
        "html": message["attachment"].nil? ? (BotApi.body_html(message["body"]) rescue "") : ""
      },
      "creator": BotApi.user(creator, base_url),
      "room": {"id": BotApi.id(message["room_id"])},
      "url": base_url + "/rooms/" + message["room_id"] + "/messages/" + message["_key"]
    }
  end

  static def messages(messages, base_url)
    creators = {}
    keys = messages.map { |m| m["creator_id"] }.uniq
    for u in User.find_many(keys)
      creators[u["_key"]] = u
    end
    messages.map { |m| BotApi.message(m, base_url, creators) }
  end

  static def boost(boost, message, base_url)
    {
      "id": BotApi.id(boost["_key"]),
      "content": boost["content"],
      "created_at": BotApi.time(boost["created_at"]),
      "booster": BotApi.user(User.find_hash(boost["booster_id"]), base_url),
      "message": {"id": BotApi.id(message["_key"]), "url": base_url + "/rooms/" + message["room_id"] + "/messages/" + message["_key"]}
    }
  end

  # message.body.to_s: the stored HTML in Action Text's layout, each attachment kept as its
  # <action-text-attachment> element (a mention without its editor content) around what its
  # partial renders. No content filters: those belong to the room's presentation.
  static def body_html(body)
    out = ""
    tokens = RichText.tokens(body ?? "")
    i = 0
    while i < tokens.length
      t = tokens[i]
      if RichText.attachment_open?(t)
        attrs = RichText.attributes(t)
        i += 1
        while i < tokens.length && !RichText.attachment_close?(tokens[i])
          i += 1
        end
        mention = !(attrs["content-type"] ?? "").contains(RichText.OPENGRAPH_TYPE)
        tag = "<action-text-attachment"
        attrs.each do |name, value|
          tag += " " + name + "=\"" + html_escape(value) + "\"" unless mention && name == "content"
        end
        out += tag + ">" + RichText.render_attachment(attrs) + "</action-text-attachment>"
      else
        out += t
      end
      i += 1
    end
    "<div class=\"lexxy-content\">\n  " + out + "\n</div>\n"
  end

  # An integer key as the number it is (JavaScript's safe range), any other as a string.
  static def id(key)
    k = str(key)
    return k unless Regex.matches("^[0-9]{1,16}$", k)

    n = int(k)
    n < 9007199254740992 ? n : k
  end

  # created_at.utc as JSON: ISO 8601 with milliseconds.
  static def time(ms)
    return nil if ms.nil?

    iso = DateTime.from_unix(ms / 1000).utc().to_iso().replace("+00:00", "")
    iso + "." + str(ms % 1000).rjust(3, "0") + "Z"
  end

  # RawRequestBody#raw_request_body
  static def raw_body(req)
    body = req["body"]
    body.is_a?("string") ? body : ""
  end

  static def json(data, status = 200, headers = {})
    all = {"Content-Type": "application/json; charset=utf-8"}
    headers.each do |k, v|
      all[k] = v
    end
    {"status": status, "headers": all, "body": json_stringify(data)}
  end
end
