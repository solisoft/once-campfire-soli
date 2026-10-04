class AccountsBotsKeysController < ApplicationController
  # PATCH /account/bots/:bot_id/key
  # PUT /account/bots/:bot_id/key — User::Bot#reset_bot_key
  def update
    @_ensure_can_administer
    bot = User.find_active_bot(req["params"]["bot_id"])
    halt(404, "") if bot.nil?

    User.reset_bot_key(bot["_key"])
    redirect("/account/bots")
  end
end
