# Room::MessagePusher: a message's notification to the recipients chosen when it was posted
# (visible, disconnected members other than the author, involved in everything or mentioned),
# through every push subscription they have.
class MessagePusher
  static def push(item)
    message = Message.find_hash(item["message_id"])
    room = Room.find_hash(item["room_id"])
    return nil if message.nil? || room.nil?

    creator = User.find_hash(message["creator_id"])
    name = creator.nil? ? "" : creator["name"]
    payload = Room.direct?(room) ?
      {"title": name, "body": message["plain_text"], "path": "/rooms/" + room["_key"]} :
      {"title": room["name"], "body": name + ": " + message["plain_text"], "path": "/rooms/" + room["_key"]}
    user_ids = item["user_ids"] ?? []
    return nil if user_ids.length == 0

    rows = Db.rows("SELECT json_object(" + Db.fields("push_subscriptions", "p") + ", 'badge', " +
                   "(SELECT count(*) FROM memberships m WHERE m.user_id = p.user_id AND m.unread_at IS NOT NULL)) AS j " +
                   "FROM push_subscriptions p WHERE p.user_id IN (" + Db.marks(user_ids) + ")", user_ids)
    for subscription in rows
      WebPush.deliver(subscription, payload)
    end
  end
end
