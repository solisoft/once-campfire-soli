class SessionsController < ApplicationController
  # GET /session/new
  def new
    return redirect("/first_run") unless User.any?

    @_render_new(200)
  end

  # POST /session — rate limited to 10 attempts per IP within three minutes.
  def create
    return @_render_rejection(429) unless RateLimit.allow?("sign_in:" + Authentication.remote_ip(req), 10, 180)

    user = User.authenticate_by(params["email_address"], params["password"])
    return @_render_rejection(401) if user.nil?

    Authentication.start_session_for(req, user)
    redirect(Authentication.post_authenticating_url)
  end

  # DELETE /session
  def destroy
    endpoint = params["push_subscription_endpoint"]
    PushSubscription.destroy_by_endpoint(@_current_user_key, endpoint) unless endpoint.blank?
    Authentication.terminate_session(req)
    redirect("/")
  end

  private

  def _render_rejection(status)
    @flash_alert = "Too many requests or unauthorized."
    @_render_new(status)
  end

  def _render_new(status)
    @page_title = "Sign in"
    @email_address = params["email_address"]
    @help_contact = Present.user(User.first_administrator)
    @layout = Layout.data(req)
    @turbo_reload = true
    render("sessions/new", {}, {"status": status})
  end
end
