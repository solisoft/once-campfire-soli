class RoomsClosedsController < ApplicationController
  # GET /rooms/closeds/:id
  def show
    return @_room_not_found unless @_set_room

    @_remember_last_room_visited
    redirect("/rooms/" + @room["_key"])
  end

  # GET /rooms/closeds/new
  def new
    @_ensure_permission_to_create_rooms
    @room = {"name": RoomForms.DEFAULT_ROOM_NAME, "type": Room.CLOSED}
    @selected_users = []
    @unselected_users = Present.users(User.active_ordered)
    @type_change_path = "/rooms/opens/new"
    @form_action = "/rooms/closeds"
    @page_title = "New chat room"
    @_render_room_page("rooms/closeds/new")
  end

  # POST /rooms/closeds
  def create
    @_ensure_permission_to_create_rooms
    attrs = params["room"]
    halt(400, "") unless attrs.is_a?("hash")

    grantees = User.find_many(RoomForms.user_ids(params, req)).map { |u| u["_key"] }
    room = Room.create_for(Room.CLOSED, attrs["name"], @_current_user_key, grantees)
    RoomForms.broadcast_created(room)
    redirect("/rooms/" + room["_key"])
  end

  # GET /rooms/closeds/:id/edit — an open room shown as the closed room it can become.
  def edit
    return @_room_not_found unless @_set_room

    @room["type"] = Room.CLOSED
    members = Room.user_keys(@room["_key"])
    users = Present.users(User.active_ordered)
    @selected_users = users.filter { |u| members.include?(u["_key"]) }
    @unselected_users = users.filter { |u| !members.include?(u["_key"]) }
    @type_change_path = "/rooms/opens/" + @room["_key"] + "/edit"
    @page_title = "Edit settings for " + (@room["name"] ?? "")
    @_render_room_page("rooms/closeds/edit")
  end

  # PATCH /rooms/closeds/:id
  # PUT /rooms/closeds/:id — saving makes the room closed and revises who is in it.
  def update
    return @_room_not_found unless @_set_room

    @_ensure_can_administer(@room)
    attrs = params["room"]
    halt(400, "") unless attrs.is_a?("hash")

    @room = Room.update_settings(@room, Room.CLOSED, attrs["name"])
    grantee_ids = RoomForms.user_ids(params, req)
    granted = User.find_many(grantee_ids).map { |u| u["_key"] }
    revoked = Room.user_keys(@room["_key"]).filter { |k| !grantee_ids.include?(k) }
    Membership.grant(@room, granted)
    Membership.revoke(@room["_key"], revoked)
    RoomForms.broadcast_updated(@room)
    redirect("/rooms/" + @room["_key"])
  end

  private

  def _set_room
    @room = RoomForms.find_room(@_current_user_key, req["params"]["id"], false)
    return false if @room.nil?

    @can_administer = User.can_administer?(@_current_user, @room)
    @current_user_key = @_current_user_key
    @form_action = "/rooms/closeds/" + @room["_key"]
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
