# RemoveBannedContentJob: User::Bannable#remove_banned_content, every message of the banned
# user destroyed and removed from the rooms it is shown in (Message#broadcast_remove).
class RemoveBannedContentJob
  static def perform(args)
    for message in Message.created_by(args["user_id"])
      Message.destroy_message(message)
      stream = "room:" + message["room_id"] + ":messages"
      Cable.broadcast_stream(stream, TurboStream.remove("message_" + message["client_message_id"]))
    end
  end
end
