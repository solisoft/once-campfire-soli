class RoomsController < ApplicationController
  # GET /rooms
  def index
    room = Room.last_for_user(@_current_user_key)
    return redirect("/") if room.nil?

    redirect("/rooms/" + room["_key"])
  end

  # GET /rooms/:id
  # GET /rooms/:room_id/@:message_id
  def show
    room_key = req["params"]["id"] ?? req["params"]["room_id"]
    at_message = req["params"]["at_message"]
    halt(404, "") if !at_message.nil? && !at_message.starts_with("@")

    page = RoomPage.load(@_current_user_key, room_key, at_message.nil? ? nil : at_message.substring(1, at_message.length))
    if page.nil?
      @_flash("alert", "Room not found or inaccessible")
      return redirect("/")
    end

    @room = page["room"]
    @_remember_last_room_visited
    base = RoomPage.base_url(req)
    account = req["account"]
    agent = req["headers"]["user-agent"] ?? ""
    sig = json_stringify([base, account["updated_at"], account["join_code"], @_current_user["updated_at"], @_current_user["role"],
                          @room["name"], @room["type"], page["display_name"], page["invitation"], Crypto.md5(agent)])
    content_sig = json_stringify([page["sig"], page["keys"]])
    csrf = csrf_token()

    # The whole response, kept per user and room while nothing it shows has changed.
    full_name = "room_full:" + @_current_user_key + ":" + @room["_key"]
    full_key = sig + content_sig + csrf + str(@room["updated_at"])
    cacheable = at_message.nil? && !page["html"].nil? && !session_has("flash_notice") && !session_has("flash_alert")
    if cacheable
      full = PageCache.get(full_name)
      return @_keep(full["response"]) if !full.nil? && full["key"] == full_key
    end

    @page_title = page["display_name"]
    @body_class = "sidebar"
    @room_page = page
    @current_user = Present.user(@_current_user)
    @messages_stream = Cable.signed_stream_name("room:" + @room["_key"] + ":messages")
    @room_page_url = base + "/rooms/" + @room["_key"] + "/messages"
    @room_refresh_url = base + "/rooms/" + @room["_key"] + "/refresh"
    @edit_room_path = RoomPage.edit_path(@room)
    @join_url = base + "/join/" + account["join_code"]
    @join_qr_path = "/qr_code/" + Base64.urlsafe_encode(@join_url)
    @notification_help_html = NotificationHelp.cached_html(req, agent)
    response = @_render_cached_page("rooms/show", "room_show:" + @_current_user_key + ":" + @room["_key"], sig, {
      "messages": RoomPage.messages_html(page, base), "csrf": csrf, "loaded_at": str(@room["updated_at"])
    }, content_sig)
    PageCache.set_bounded(full_name, {"key": full_key, "response": response}, "room_full", 64) if cacheable
    @_keep(response)
  end

  # DELETE /rooms/:id
  def destroy
    room = RoomPage.room_for(@_current_user_key, req["params"]["id"])
    if room.nil?
      @_flash("alert", "Room not found or inaccessible")
      return redirect("/")
    end

    @_ensure_can_administer(room)
    Room.destroy_room(room)
    Cable.broadcast_stream("rooms", TurboStream.remove(Room.dom_id(room, "list")))
    redirect("/")
  end
end
