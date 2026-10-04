class UsersPushSubscriptionsTestNotificationsController < ApplicationController
  # POST /users/:user_id/push_subscriptions/:push_subscription_id/test_notifications
  def create
    subscription = PushSubscription.find_for_user(@_current_user_key, req["params"]["push_subscription_id"])
    halt(404, "") if subscription.nil?

    path = RoomPage.base_url(req) + "/users/me/push_subscriptions"
    payload = {"title": "Campfire Test", "body": UUID.v4(), "path": path}
    WebPush.deliver(PushSubscription.with_badge(subscription), payload)
    redirect("/users/me/push_subscriptions")
  end
end
