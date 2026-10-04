class WelcomeController < ApplicationController
  # GET /
  def show
    room = @_last_room_visited
    return redirect("/rooms/" + room["_key"]) unless room.nil?

    @page_title = "No rooms yet"
    @body_class = "sidebar"
    @_render_page("welcome/show")
  end
end
