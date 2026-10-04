class MessagesController < ApplicationController
  # GET /rooms/:room_id/messages — a page of messages, before or after one, or the last.
  def index
    @_set_room_scoped(req["params"]["room_id"])
    page = MessagePage.load(@room["_key"], params["before"], params["after"], RoomPage.base_url(req))
    halt(404, "") if page.nil?
    return @_head(204) if page["count"] == 0

    {"status": 200, "headers": {"Content-Type": "text/html; charset=utf-8"}, "body": page["html"]}
  end

  # POST /rooms/:room_id/messages
  def create
    found = Membership.with_room_for(@_current_user_key, req["params"]["room_id"])
    return render("messages/room_not_found", {}, {"layout": false}) if found.nil?

    @room = found["room"]
    attrs = params["message"] ?? {}
    attachment = Attachments.create_message_attachment(find_uploaded_file(req, "message[attachment]"))
    created = Message.create_message(@room, @_current_user, attrs["body"], attachment, attrs["client_message_id"], RoomPage.base_url(req))
    message = created["message"]
    html = message["html"]
    Broadcasts.message_created(@room, created["members"], html)
    Bots.deliver_webhooks(@room, message, @_current_user_key)
    @_turbo_stream(TurboStream.append(Room.dom_id(@room, "messages"), html))
  end

  # GET /rooms/:room_id/messages/:id
  def show
    @_set_room_scoped(req["params"]["room_id"])
    message = Message.find_in_room(@room["_key"], req["params"]["id"])
    halt(404, "") if message.nil?

    {"status": 200, "headers": {"Content-Type": "text/html; charset=utf-8"}, "body": MessagePresenter.join([message], RoomPage.base_url(req))}
  end

  private

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
end
