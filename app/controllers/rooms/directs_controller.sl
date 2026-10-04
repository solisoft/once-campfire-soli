class RoomsDirectsController < ApplicationController
  # GET /rooms/directs/new — the autocomplete form, in the sidebar's direct_rooms_control frame.
  def new
    @_render_room_page("rooms/directs/new")
  end

  # POST /rooms/directs — user_ids[] from the form, or from the query string of button_to.
  def create
    me = @_current_user_key
    keys = User.find_many(RoomForms.user_ids(params, req) + [me]).map { |u| u["_key"] }
    room = Room.find_direct_for(keys)
    room = Room.create_for(Room.DIRECT, nil, me, keys) if room.nil?
    RoomForms.broadcast_direct_created(room)
    redirect("/rooms/" + room["_key"])
  end

  # GET /rooms/directs/:id/edit
  def edit
    return @_room_not_found unless @_set_room

    users = Present.users(Room.users(@room["_key"]))
    others = users.filter { |u| u["_key"] != @_current_user_key }
    @users = users.length > 1 ? others : users
    @page_title = "Edit settings for " + RoomPage.display_name(@room, users, @_current_user_key)
    @delete_room_url = RoomPage.base_url(req) + "/rooms/directs/" + @room["_key"]
    @_render_room_page("rooms/directs/edit")
  end

  # DELETE /rooms/directs/:id — any member may delete a direct room.
  def destroy
    return @_room_not_found unless @_set_room

    Room.destroy_room(@room)
    Cable.broadcast_stream("rooms", TurboStream.remove(Room.dom_id(@room, "list")))
    redirect("/")
  end

  private

  def _set_room
    @room = RoomForms.find_room(@_current_user_key, req["params"]["id"], true)
    !@room.nil?
  end

  def _room_not_found
    @_flash("alert", "Room not found or inaccessible")
    redirect("/")
  end

  def _render_room_page(view)
    last = @_last_room_visited
    @back_path = last.nil? ? "/" : "/rooms/" + last["_key"]
    return @_render_page(view) unless RoomForms.frame_request?(req)

    response = render(view, {}, {"layout": false})
    response["body"] = RoomForms.frame_body(response["body"], csrf_token())
    response
  end
end
