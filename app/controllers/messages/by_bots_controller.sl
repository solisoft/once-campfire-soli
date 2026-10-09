# The bot API: a bot, authenticated by the bot_key path segment, reads and posts messages in
# the rooms it belongs to. Bodies are the raw request body (text or HTML), or a multipart
# "attachment" field.
class MessagesByBotsController < ApplicationController
  # GET /rooms/:room_id/:bot_key/messages — a page of messages, with X-Total-Count and a
  # Link to the next page.
  def index
    return @_head(404) unless @_set_room

    rk = @room["_key"]
    messages = @_find_paged_messages
    base = RoomPage.base_url(req)
    headers = {"X-Total-Count": str(Message.count_in_room(rk))}
    next_page = @_next_page_params(messages)
    unless next_page.nil?
      url = base + "/rooms/" + rk + "/" + req["params"]["bot_key"] + "/messages?" + next_page[0] + "=" + next_page[1]
      headers["Link"] = "<" + url + ">; rel=\"next\""
    end
    BotApi.json(BotApi.messages(messages, base), 200, headers)
  end

  # POST /rooms/:room_id/:bot_key/messages — 201 with the message's Location.
  def create
    room_key = req["params"]["room_id"]
    return @_head(404) if Membership.find_for(@_current_user_key, room_key).nil?

    file = find_uploaded_file(req, "attachment")
    body = BotApi.raw_body(req)
    return @_head(422) if file.nil? && body.blank?

    base = RoomPage.base_url(req)
    attachment = Attachments.create_message_attachment(file)
    created = Message.post(room_key, @_current_user, attachment.nil? ? body : nil, attachment, nil, base)
    return @_head(404) if created.nil?

    @room = created["room"]
    message = created["message"]
    Broadcasts.message_created(@room, created["members"], message["html"])
    Bots.deliver_webhooks(@room, message, @_current_user_key)
    @_head(201, {"Location": base + "/messages/" + message["_key"]})
  end

  # PATCH /rooms/:room_id/:bot_key/messages/:id
  # PUT /rooms/:room_id/:bot_key/messages/:id — the bot's own messages only.
  def update
    return @_head(404) unless @_set_room

    message = @_find_message
    return @_head(404) if message.nil?
    return @_head(403) unless User.can_administer?(@_current_user, message)

    base = RoomPage.base_url(req)
    updated = MessageEdits.update(@room, message, BotApi.raw_body(req), base)
    BotApi.json(BotApi.message(updated, base))
  end

  # DELETE /rooms/:room_id/:bot_key/messages/:id
  def destroy
    return @_head(404) unless @_set_room

    message = @_find_message
    return @_head(404) if message.nil?
    return @_head(403) unless User.can_administer?(@_current_user, message)

    MessageEdits.destroy(@room, message)
    @_head(204)
  end

  private

  # Current.user.rooms.find_by(id: params[:room_id])
  def _set_room
    @room = RoomPage.room_for(@_current_user_key, req["params"]["room_id"])
    !@room.nil?
  end

  def _find_message
    Message.find_in_room(@room["_key"], req["params"]["id"])
  end

  def _find_paged_messages
    rk = @room["_key"]
    unless params["before"].blank?
      anchor = Message.find_in_room(rk, params["before"])
      halt(404, "") if anchor.nil?

      return Message.page_before(rk, anchor)
    end
    unless params["after"].blank?
      anchor = Message.find_in_room(rk, params["after"])
      halt(404, "") if anchor.nil?

      return Message.page_after(rk, anchor)
    end
    Message.last_page(rk)
  end

  def _next_page_params(messages)
    return nil if messages.length == 0

    rk = @room["_key"]
    unless params["after"].blank?
      last = messages.last
      return Message.exists_after?(rk, last) ? ["after", last["_key"]] : nil
    end
    first = messages[0]
    Message.exists_before?(rk, first) ? ["before", first["_key"]] : nil
  end
end
