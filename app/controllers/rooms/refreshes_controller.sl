class RoomsRefreshesController < ApplicationController
  # GET /rooms/:room_id/refresh?since=MS — what a room missed while the page was away: new
  # messages appended, edited or boosted ones replaced.
  def show
    @_set_room_scoped(req["params"]["room_id"])
    since = (params["since"] ?? "").to_i
    rk = @room["_key"]
    base = RoomPage.base_url(req)
    created = Message.page_created_since(rk, since)
    updated = Message.page_updated_since(rk, since, created.map { |m| m["_key"] })
    streams = []
    streams.push(TurboStream.append(Room.dom_id(@room, "messages"), MessagePresenter.join(created, base))) if created.length > 0
    if updated.length > 0
      htmls = MessagePresenter.html_for(updated, base)
      i = 0
      while i < updated.length
        streams.push(TurboStream.replace("message_" + updated[i]["client_message_id"], htmls[i]))
        i += 1
      end
    end
    @_turbo_stream(streams.join("\n"))
  end
end
