class MessagesBoostsController < ApplicationController
  # GET /messages/:message_id/boosts — the message's boosts, in their turbo frame.
  def index
    @_set_message
    boosts = (Boost.for_messages([@message["_key"]])[@message["_key"]] ?? []).map { |b| MessagePresenter.boost(b) }
    @m = {"_key": @message["_key"], "client_message_id": @message["client_message_id"],
          "boosts_html": boosts.map { |b| render_partial("messages/boosts/boost", {"boost": b}) }.join("")}
    @_render_framed("messages/boosts/index")
  end

  # GET /messages/:message_id/boosts/new
  def new
    @_set_message
    @current_user = Present.user(@_current_user)
    @_render_framed("messages/boosts/new")
  end

  # POST /messages/:message_id/boosts
  def create
    @_set_message
    attrs = params["boost"]
    halt(400, "") unless attrs.is_a?("hash")

    boost = Boost.create_boost(@message, @_current_user_key, attrs["content"])
    MessageBoosts.broadcast_create(@message, boost, RoomPage.base_url(req))
    redirect("/messages/" + @message["_key"] + "/boosts")
  end

  # DELETE /messages/:message_id/boosts/:id — only one's own boosts.
  def destroy
    @_set_message
    boost = Boost.find_hash(req["params"]["id"])
    halt(404, "") if boost.nil? || boost["message_id"] != @message["_key"] || boost["booster_id"] != @_current_user_key

    MessageBoosts.destroy(@message, boost, RoomPage.base_url(req))
    @_head(204)
  end

  private

  # Current.user.reachable_messages.find
  def _set_message
    @message = Message.find_reachable(@_current_user_key, req["params"]["message_id"])
    halt(404, "") if @message.nil?
  end

  def _render_framed(view)
    return @_render_page(view) unless RoomForms.frame_request?(req)

    response = render(view, {}, {"layout": false})
    response["body"] = RoomForms.frame_body(response["body"], csrf_token())
    response
  end
end
