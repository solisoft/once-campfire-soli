class RoomsInvolvementsController < ApplicationController
  # GET /rooms/:room_id/involvement — the bell, in its turbo frame.
  def show
    @_set_room_scoped(req["params"]["room_id"])
    @involvement = @membership["involvement"]
    return @_render_page("rooms/involvements/show") unless RoomForms.frame_request?(req)

    response = render("rooms/involvements/show", {}, {"layout": false})
    response["body"] = RoomForms.frame_body(response["body"], csrf_token())
    response
  end

  # PATCH /rooms/:room_id/involvement
  # PUT /rooms/:room_id/involvement — the next involvement in the bell's cycle.
  def update
    @_set_room_scoped(req["params"]["room_id"])
    involvement = params["involvement"]
    halt(400, "") unless Membership.INVOLVEMENTS.include?(involvement)

    previous = @membership["involvement"]
    Membership.set_involvement(@membership, involvement)
    @_broadcast_visibility_changes(previous, involvement)
    redirect("/rooms/" + @room["_key"] + "/involvement")
  end

  private

  def _broadcast_visibility_changes(previous, involvement)
    return nil if Room.direct?(@room)

    stream = "user:" + @_current_user_key + ":rooms"
    if involvement == "invisible"
      Cable.broadcast_stream(stream, TurboStream.remove(Room.dom_id(@room, "list")))
    elsif previous == "invisible"
      Cable.broadcast_stream(stream, TurboStream.prepend("shared_rooms", RoomForms.shared_html(@room)))
    end
  end
end
