# Messages::BoostsController#broadcast_create / #broadcast_remove, shared with the bot API.
# A boost touches its message (Boost.create_boost / destroy_boost), so the message's cached
# HTML is re-rendered here rather than on the room page's next load.
class MessageBoosts
  static def broadcast_create(message, boost, base_url)
    boost["booster"] = User.find_hash(boost["booster_id"])
    html = render_partial("messages/boosts/boost", {"boost": MessagePresenter.boost(boost)})
    Cable.broadcast_stream("room:" + message["room_id"] + ":messages",
      TurboStream.append("boosts_message_" + message["client_message_id"], html, {"maintain_scroll": "true"}))
    MessageEdits.refresh(message["_key"], base_url)
  end

  static def destroy(message, boost, base_url)
    Boost.destroy_boost(boost)
    Cable.broadcast_stream("room:" + message["room_id"] + ":messages", TurboStream.remove("boost_" + boost["_key"]))
    MessageEdits.refresh(message["_key"], base_url)
  end
end
