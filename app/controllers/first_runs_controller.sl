class FirstRunsController < ApplicationController
  static {
    this.before_action = fn(req) {
      return redirect("/") unless req["account"].nil?
      req
    }
  }

  # GET /first_run
  def show
    @page_title = "Set up Campfire"
    @body_class = "signup"
    @_render_page("first_runs/show")
  end

  # POST /first_run — FirstRun.create!: the account, the first room and its administrator.
  def create
    attrs = params["user"] ?? {}
    attrs["role"] = "administrator"
    Account.create_singleton("Campfire")
    user = User.insert(attrs)
    halt(422, "") if user.nil?

    key = user["_key"]
    Users.attach_avatar(key, find_uploaded_file(req, "user[avatar]"))
    Room.create_for(Room.OPEN, "All Talk", key, [key])
    Authentication.start_session_for(req, User.find_hash(key))
    redirect("/")
  end
end
