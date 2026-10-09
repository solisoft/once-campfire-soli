class AccountsBotsController < ApplicationController
  # GET /account/bots
  def index
    @_ensure_can_administer
    base = RoomPage.base_url(req)
    @page_title = "Chat bots"
    @bots = Present.users(User.active_bots_ordered).map { |bot|
      bot_key = User.bot_key(bot)
      bot["rooms"] = Membership.rooms_without_directs_for(bot["_key"]).map { |room|
        {"name": room["name"], "messages_url": base + "/rooms/" + room["_key"] + "/" + bot_key + "/messages"}
      }
      bot
    }
    @_render_page("accounts/bots/index")
  end

  # GET /account/bots/new
  def new
    @_ensure_can_administer
    @page_title = "New chat bot"
    @bot = {"name": nil, "webhook_url": nil, "avatar_url": nil}
    @_render_page("accounts/bots/new")
  end

  # POST /account/bots — User.create_bot!
  def create
    @_ensure_can_administer
    attrs = @_bot_params
    bot = User.create_user({"name": attrs["name"], "role": "bot", "bot_token": User.generate_bot_token})
    halt(422, "") if bot.nil?

    Users.attach_avatar(bot["_key"], find_uploaded_file(req, "user[avatar]"))
    Webhook.set_url(bot["_key"], attrs["webhook_url"])
    redirect("/account/bots")
  end

  # GET /account/bots/:id/edit
  def edit
    @_ensure_can_administer
    bot = @_set_bot
    webhook = Webhook.for_user(bot["_key"])
    avatar = bot["avatar"]
    @page_title = "Edit bot"
    @bot = {
      "_key": bot["_key"], "name": bot["name"], "webhook_url": webhook.nil? ? nil : webhook["url"],
      "avatar_url": avatar.nil? ? nil : Attachments.path(avatar["blob_id"], avatar["filename"])
    }
    @_render_page("accounts/bots/edit")
  end

  # PATCH /account/bots/:id
  # PUT /account/bots/:id — User::Bot#update_bot!
  def update
    @_ensure_can_administer
    bot = @_set_bot
    attrs = @_bot_params
    Webhook.set_url(bot["_key"], attrs["webhook_url"])
    fields = {"updated_at": Clock.now}
    fields["name"] = attrs["name"] unless attrs["name"].nil?
    Db.update_row("users", bot["_key"], fields)
    Users.attach_avatar(bot["_key"], find_uploaded_file(req, "user[avatar]"))
    redirect("/account/bots")
  end

  # DELETE /account/bots/:id
  def destroy
    @_ensure_can_administer
    User.deactivate(@_set_bot)
    redirect("/account/bots")
  end

  private

  def _set_bot
    bot = User.find_active_bot(req["params"]["id"])
    halt(404, "") if bot.nil?

    bot
  end

  def _bot_params
    attrs = params["user"]
    attrs = {} unless attrs.is_a?("hash")
    {"name": attrs["name"].is_a?("string") ? attrs["name"] : nil,
     "webhook_url": attrs["webhook_url"].is_a?("string") ? attrs["webhook_url"] : nil}
  end
end
