# The bot API's boosts: the raw request body is the boost's content.
class MessagesBoostsByBotsController < ApplicationController
  # POST /rooms/:room_id/:bot_key/messages/:message_id/boosts — 201 with the boost as JSON.
  def create
    message = @_find_message
    return @_head(404) if message.nil?

    content = BotApi.raw_body(req)
    return @_head(422) if content.blank?

    base = RoomPage.base_url(req)
    boost = Boost.create_boost(message, @_current_user_key, content)
    MessageBoosts.broadcast_create(message, boost, base)
    BotApi.json(BotApi.boost(boost, message, base), 201)
  end

  # DELETE /rooms/:room_id/:bot_key/messages/:message_id/boosts/:id — the bot's own boosts.
  def destroy
    message = @_find_message
    return @_head(404) if message.nil?

    boost = Boost.find_hash(req["params"]["id"])
    return @_head(404) if boost.nil? || boost["message_id"] != message["_key"] || boost["booster_id"] != @_current_user_key

    MessageBoosts.destroy(message, boost, RoomPage.base_url(req))
    @_head(204)
  end

  private

  # A message of a room the bot belongs to.
  def _find_message
    room = RoomPage.room_for(@_current_user_key, req["params"]["room_id"])
    return nil if room.nil?

    Message.find_in_room(room["_key"], req["params"]["message_id"])
  end
end
