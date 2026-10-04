# MessagesController#update and #destroy, shared with the bot API: the write, the broadcast
# to the room, and the cached message HTML brought up to date so the room page doesn't have
# to re-render the message on its next load.
class MessageEdits
  static def update(room, message, body_html, base_url)
    updated = Message.update_body(message, body_html)
    creator = Present.user(User.find_hash(updated["creator_id"]))
    unless creator.nil?
      data = MessagePresenter.data(updated, creator, [], "", base_url)
      html = render_partial("messages/presentation", {"m": data})
      Cable.broadcast_stream("room:" + room["_key"] + ":messages",
        TurboStream.replace("presentation_message_" + updated["client_message_id"], html, {"maintain_scroll": "true"}))
    end
    MessagePresenter.html_for([updated], base_url)
    updated
  end

  # @message.destroy + broadcast_remove
  static def destroy(room, message)
    Message.destroy_message(message)
    Cable.broadcast_stream("room:" + room["_key"] + ":messages", TurboStream.remove("message_" + message["client_message_id"]))
  end

  # Boost's belongs_to :message, touch: true: the message re-rendered with its boosts now.
  static def refresh(message_key, base_url)
    message = Message.find_hash(message_key)
    MessagePresenter.html_for([message], base_url) unless message.nil?
  end
end
