class UsersBansController < ApplicationController
  static {
    this.before_action(:create, :destroy) = fn(req) {
      halt(403, "") unless User.can_administer?(req["current_user"])
      req
    }
  }

  # POST /users/:user_id/ban — User::Bannable#ban: bans from the user's session IPs, its
  # connections closed and sessions ended, then its messages removed in the background.
  def create
    user = @_find_user
    key = user["_key"]
    for ip in Session.ip_addresses_for_user(key)
      Ban.create_for(key, ip)
    end
    Cable.disconnect_user(key, false)
    Session.destroy_for_user(key)
    User.update(key, {"status": "banned", "updated_at": Clock.now})
    RemoveBannedContentJob.perform_later({"user_id": key})
    redirect("/users/" + key)
  end

  # DELETE /users/:user_id/ban — User::Bannable#unban
  def destroy
    user = @_find_user
    Ban.delete_for_user(user["_key"])
    User.update(user["_key"], {"status": "active", "updated_at": Clock.now})
    redirect("/users/" + user["_key"])
  end

  private

  def _find_user
    user = User.find_hash(req["params"]["user_id"])
    halt(404, "") if user.nil?

    user
  end
end
