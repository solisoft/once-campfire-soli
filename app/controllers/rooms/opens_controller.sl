class RoomsOpensController < ApplicationController
  # GET /rooms/opens/:id
  def show
    return @_room_not_found unless @_set_room

    @_remember_last_room_visited
    redirect("/rooms/" + @room["_key"])
  end

  # GET /rooms/opens/new
  def new
    @_ensure_permission_to_create_rooms
    @room = {"name": RoomForms.DEFAULT_ROOM_NAME, "type": Room.OPEN}
    @users = Present.users(User.active_ordered)
    @type_change_path = "/rooms/closeds/new"
    @form_action = "/rooms/opens"
    @page_title = "New chat room"
    @_render_room_page("rooms/opens/new")
  end

  # POST /rooms/opens
  def create
    @_ensure_permission_to_create_rooms
    attrs = params["room"]
    halt(400, "") unless attrs.is_a?("hash")

    room = Room.create_for(Room.OPEN, attrs["name"], @_current_user_key, [@_current_user_key])
    RoomForms.broadcast_created(room)
    redirect("/rooms/" + room["_key"])
  end

  # GET /rooms/opens/:id/edit — a closed room shown as the open room it can become.
  def edit
    return @_room_not_found unless @_set_room

    @room["type"] = Room.OPEN
    @users = Present.users(User.active_ordered)
    @type_change_path = "/rooms/closeds/" + @room["_key"] + "/edit"
    @page_title = "Edit settings for " + (@room["name"] ?? "")
    @_render_room_page("rooms/opens/edit")
  end

  # PATCH /rooms/opens/:id
  # PUT /rooms/opens/:id — saving makes the room open.
  def update
    return @_room_not_found unless @_set_room

    @_ensure_can_administer(@room)
    attrs = params["room"]
    halt(400, "") unless attrs.is_a?("hash")

    @room = Room.update_settings(@room, Room.OPEN, attrs["name"])
    RoomForms.broadcast_updated(@room)
    redirect("/rooms/" + @room["_key"])
  end

  private

  def _set_room
    @room = RoomForms.find_room(@_current_user_key, req["params"]["id"], false)
    return false if @room.nil?

    @can_administer = User.can_administer?(@_current_user, @room)
    @form_action = "/rooms/opens/" + @room["_key"]
    @delete_room_url = RoomPage.base_url(req) + "/rooms/" + @room["_key"]
    true
  end

  def _room_not_found
    @_flash("alert", "Room not found or inaccessible")
    redirect("/")
  end

  def _ensure_permission_to_create_rooms
    halt(403, "") unless RoomForms.can_create?(@_current_user, @_account)

    @can_administer = true
    @current_user_key = @_current_user_key
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
