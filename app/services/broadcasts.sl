# The Turbo Stream and Action Cable broadcasts of the reference's models and controllers.
class Broadcasts
  # Message::Broadcasts#broadcast_create: the message to the room's stream, and an unread
  # ping to each member (UnreadRoomsChannel, per user).
  static def message_created(room, member_keys, html)
    Cable.broadcast_stream("room:" + room["_key"] + ":messages", TurboStream.append(Room.dom_id(room, "messages"), html))
    payload = json_stringify({"roomId": Cable.numeric(room["_key"])})
    for user_key in member_keys
      Cable.broadcast_raw("user_" + user_key + "_unreads", payload)
    end
  end
end
