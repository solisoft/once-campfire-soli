class AccountsUsersController < ApplicationController
  static PER_PAGE: Int = 500

  # GET /account/users?page=N — the next page of people, as Turbo Stream actions.
  def index
    page = int(params["page"] ?? "1") rescue 1
    page = 1 if page < 1
    users = User.account_users_ordered(false)
    per = AccountsUsersController.PER_PAGE
    records = Present.users(users.drop((page - 1) * per).take(per))
    me = Present.user(@_current_user)
    can_administer = User.can_administer?(@_current_user)
    html = records.map { |u|
      render_partial("accounts/users/user", {"user": u, "current_user": me, "can_administer": can_administer})
    }.join("")
    body = TurboStream.replace("next_page_container", html)
    if users.length > page * per
      next_page = render_partial("accounts/users/next_page_container", {"page": page + 1})
      body += "\n" + TurboStream.append("account_users", next_page)
    end
    @_turbo_stream(body)
  end

  # PATCH /account/users/:id
  # PUT /account/users/:id
  def update
    @_ensure_can_administer
    user = @_set_user
    attrs = params["user"]
    role = attrs.is_a?("hash") ? attrs["role"] : nil
    role = "member" unless ["member", "administrator"].include?(role)
    User.set_role(user["_key"], role)
    redirect("/account/edit")
  end

  # DELETE /account/users/:id — deactivates the person.
  def destroy
    @_ensure_can_administer
    User.deactivate(@_set_user)
    redirect("/account/edit")
  end

  private

  def _set_user
    user = User.find_active(req["params"]["id"])
    halt(404, "") if user.nil?

    user
  end
end
