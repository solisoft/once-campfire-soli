# The Turbo Stream and Action Cable broadcasts of the reference's models and controllers.
class Broadcasts
  # Message::Broadcasts#broadcast_create: the message to the room's stream, and an unread
  # ping to each member (UnreadRoomsChannel, per user).
  static def message_created(room, member_keys, html)
    Cable.broadcast_stream("room:" + room["_key"] + ":messages", TurboStream.append(Room.dom_id(room, "messages"), html))
    identifier = json_stringify({"channel": "UnreadRoomsChannel"})
    message = json_stringify({"identifier": identifier, "message": {"roomId": Cable.numeric(room["_key"])}})
    for user_key in member_keys
      Cable.send_to_channel(Cable.channel_name("user_" + user_key + "_unreads", identifier), message)
    end
  end
end
