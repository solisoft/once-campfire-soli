class AccountsController < ApplicationController
  static PER_PAGE: Int = 500
  static LOGO_VARIANTS: Hash = {"large": {"size": 512, "format": "png"}, "small": {"size": 192, "format": "png"}}

  # GET /account/edit
  def edit
    account = @_account
    can_administer = User.can_administer?(@_current_user)
    users = Present.users(User.account_users_ordered(can_administer))
    @page_title = "Account settings"
    @account = account
    @current_user = Present.user(@_current_user)
    @can_administer = can_administer
    @administrators = users.filter { |u| u["administrator"] }
    @members = users.filter { |u| !u["administrator"] }
    @next_page = users.length > AccountsController.PER_PAGE ? 2 : nil
    @restrict_room_creation = Account.restrict_room_creation?(account)
    @logo_attached = !account["logo"].nil?
    @logo_path = Present.logo_path(account)
    last_room = @_last_room_visited
    @back_path = last_room.nil? ? "/" : "/rooms/" + last_room["_key"]
    @join_url = RoomPage.base_url(req) + "/join/" + account["join_code"]
    @join_qr_path = "/qr_code/" + Base64.urlsafe_encode(@join_url)
    @version = getenv("APP_VERSION") ?? getenv("GIT_REVISION") ?? "0"
    @_render_page("accounts/edit")
  end

  # PATCH /account
  # PUT /account
  def update
    @_ensure_can_administer
    attrs = params["account"]
    attrs = {} unless attrs.is_a?("hash")
    fields = {}
    fields["name"] = attrs["name"] if attrs["name"].is_a?("string")
    settings = attrs["settings"]
    if settings.is_a?("hash") && !settings["restrict_room_creation_to_administrators"].nil?
      current = @_account["settings"] ?? {}
      merged = {}
      current.each do |k, v|
        merged[k] = v
      end
      value = str(settings["restrict_room_creation_to_administrators"])
      merged["restrict_room_creation_to_administrators"] = value == "true" || value == "1"
      fields["settings"] = merged
    end
    file = find_uploaded_file(req, "account[logo]")
    if !file.nil? && file["size"] > 0
      Attachments.delete_image_set(@_account["logo"]) unless @_account["logo"].nil?
      fields["logo"] = Attachments.create_image_set(file, AccountsController.LOGO_VARIANTS)
    end
    Account.update_fields(fields)
    @_flash("notice", "✓")
    redirect("/account/edit")
  end
end
