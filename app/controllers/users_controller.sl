class UsersController < ApplicationController
  static {
    this.before_action(:new, :create) = fn(req) {
      account = req["account"]
      halt(404, "") if account.nil? || account["join_code"] != req["params"]["join_code"]
      req
    }
  }

  # GET /join/:join_code
  def new
    @page_title = "Sign up"
    @body_class = "signup"
    @join_code = req["params"]["join_code"]
    @help_contact = Present.user(User.first_administrator)
    @_render_page("users/new")
  end

  # POST /join/:join_code — the new user, signed in; an email already taken goes to sign in.
  def create
    attrs = permit(params["user"] ?? {}, {"name": true, "email_address": true, "password": true})
    user = User.create_user(attrs)
    return redirect("/session/new?email_address=" + url_encode(attrs["email_address"].to_s)) if user.nil?

    Users.attach_avatar(user["_key"], find_uploaded_file(req, "user[avatar]"))
    Authentication.start_session_for(req, User.find_hash(user["_key"]))
    redirect("/")
  end

  # GET /users/:id
  def show
    user = User.find_hash(req["params"]["id"])
    halt(404, "") if user.nil?

    @user = Present.user(user)
    @page_title = user["name"]
    @is_self = user["_key"] == @_current_user_key
    @can_administer = User.can_administer?(@_current_user)
    @back_url = SessionTransfers.back_url(req)
    @transfer = SessionTransfers.link(req, user, @_current_user) if @can_administer && user["status"] == "active"
    @_render_page("users/show")
  end
end
