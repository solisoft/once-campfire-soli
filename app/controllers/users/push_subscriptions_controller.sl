class UsersPushSubscriptionsController < ApplicationController
  # GET /users/:user_id/push_subscriptions — always the signed-in user's own.
  def index
    @page_title = "Push notification subscriptions"
    last_room = @_last_room_visited
    @back_url = last_room.nil? ? "/" : "/rooms/" + last_room["_key"]
    @push_subscriptions = PushSubscription.for_user(@_current_user_key).map { |s|
      s["agent"] = ApplicationPlatform.describe(s["user_agent"])
      s
    }
    @_render_page("users/push_subscriptions/index")
  end

  # POST /users/:user_id/push_subscriptions — 200 when stored (or already stored and still
  # valid), 422 otherwise; empty bodies either way.
  def create
    attrs = permit(params["push_subscription"] ?? {}, {"endpoint": true, "p256dh_key": true, "auth_key": true})
    me = @_current_user_key
    existing = PushSubscription.find_matching(me, attrs["endpoint"], attrs["p256dh_key"], attrs["auth_key"])
    unless existing.nil?
      return @_head(422) unless PushSubscription.endpoint_error(existing["endpoint"]).nil?

      PushSubscription.touch(existing["_key"])
      return @_head(200)
    end

    agent = req["headers"]["user-agent"]
    created = PushSubscription.create_for(me, attrs["endpoint"], attrs["p256dh_key"], attrs["auth_key"], agent)
    @_head(created.nil? || (created._errors && created._errors.length > 0) ? 422 : 200)
  end

  # DELETE /users/:user_id/push_subscriptions/:id
  def destroy
    PushSubscription.destroy_for(@_current_user_key, req["params"]["id"])
    redirect("/users/me/push_subscriptions")
  end
end
