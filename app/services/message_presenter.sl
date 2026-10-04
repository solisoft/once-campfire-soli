# messages/_message.html.erb with `cache [ message, "presentation-v3" ]`: each message's HTML
# is rendered once per version and kept on the message document itself, so a page of
# messages is one query and a string join. A boost or an edit moves updated_at, which is
# part of the key, exactly as touching the record expires the Rails fragment.
class MessagePresenter
  static VERSION: String = "presentation-v3"

  static def cache_key(message)
    MessagePresenter.VERSION + ":" + str(message["updated_at"])
  end

  # The HTML of each message, in order, rendering and storing the stale ones.
  static def html_for(messages, base_url)
    stale = messages.filter { |m| m["html_key"] != MessagePresenter.cache_key(m) || m["html"].nil? }
    rendered = {}
    if stale.length > 0
      for item in MessagePresenter.render_all(stale, base_url)
        rendered[item[0]] = item[1]
      end
    end
    messages.map { |m| rendered[m["_key"]] ?? m["html"] }
  end

  static def join(messages, base_url)
    MessagePresenter.html_for(messages, base_url).join("\n")
  end

  static def render_all(messages, base_url)
    creator_keys = messages.map { |m| m["creator_id"] }.uniq
    creators = {}
    for u in User.find_many(creator_keys)
      creators[u["_key"]] = Present.user(u)
    end
    boosts = Boost.for_messages(messages.map { |m| m["_key"] })
    room_names = {}
    results = []
    for message in messages
      creator = creators[message["creator_id"]]
      html = nil
      if creator.nil?
        html = render_partial("messages/unrenderable", {})
      else
        rk = message["room_id"]
        if room_names[rk].nil?
          room = Room.find_hash(rk)
          room_names[rk] = room.nil? ? "" : Room.display_name(room, nil)
        end
        data = MessagePresenter.data(message, creator, boosts[message["_key"]] ?? [], room_names[rk], base_url)
        html = render_partial("messages/message", {"m": data})
      end
      Message.save_html(message["_key"], html, MessagePresenter.cache_key(message))
      results.push([message["_key"], html])
    end
    results
  end

  static def data(message, creator, boosts, room_name, base_url)
    permalink = "/rooms/" + message["room_id"] + "/@" + message["_key"]
    content_type = Message.content_type(message)
    data = {
      "_key": message["_key"], "client_message_id": message["client_message_id"],
      "creator_id": message["creator_id"], "creator": creator, "room_id": message["room_id"],
      "created_at": message["created_at"], "updated_at": message["updated_at"],
      "room_name": room_name, "permalink_path": permalink, "permalink_url": base_url + permalink,
      "content_type": content_type, "attachment": message["attachment"],
      "emoji": Emoji.all_emoji?(message["plain_text"]),
      "boosts": boosts.map { |b| MessagePresenter.boost(b) }
    }
    if content_type == "attachment"
      a = message["attachment"]
      data["blob_path"] = Attachments.path(a["blob_id"], a["filename"])
      data["download_path"] = Attachments.path(a["blob_id"], a["filename"], "attachment")
    end
    data["presentation_html"] = MessagePresenter.presentation(message, content_type, data)
    data
  end

  # A message about to be stored: its author is at hand and it has no boosts yet.
  static def render_new(message, creator, room, base_url)
    room_name = Room.direct?(room) ? Room.display_name(room, nil) : room["name"]
    data = MessagePresenter.data(message, Present.user(creator), [], room_name, base_url)
    render_partial("messages/message", {"m": data})
  end

  static def boost(boost)
    boost["booster"] = Present.user(boost["booster"]) unless boost["booster"].nil?
    boost["booster"] = {"_key": boost["booster_id"], "name": "", "title": "", "avatar_path": ""} if boost["booster"].nil?
    boost["emoji"] = Emoji.all_emoji?(boost["content"])
    boost
  end

  # MessagesHelper#message_presentation
  static def presentation(message, content_type, data)
    if content_type == "attachment"
      return render_partial("messages/attachment", {"m": data, "a": AttachmentPresentation.data(message["attachment"], data)})
    end
    if content_type == "sound"
      return render_partial("messages/sound", {"sound": Sounds.from_body(message["plain_text"])})
    end
    RichText.render(message["body"]) rescue ""
  end
end
