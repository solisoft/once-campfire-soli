class SessionsTransfersController < ApplicationController
  # GET /session/transfers/:id — a form that submits itself (FormsHelper#auto_submit_form_with).
  def show
    @transfer_id = req["params"]["id"]
    @_render_page("sessions/transfers/show")
  end

  # PUT /session/transfers/:id
  # PATCH /session/transfers/:id — signs in the active user the link was made for.
  def update
    user = User.find_by_transfer_id(req["params"]["id"])
    return @_head(400) if user.nil? || user["status"] != "active"

    Authentication.start_session_for(req, user)
    redirect(Authentication.post_authenticating_url)
  end
end
