class UsersProfilesController < ApplicationController
  # GET /users/:user_id/profile — always the signed-in user's own.
  def show
    user = @_current_user
    shared = []
    directs = []
    for m in Membership.with_rooms_and_other_names_for(@_current_user_key)
      if m["room"]["type"] == Room.DIRECT
        m["display_name"] = m["other_names"].length > 0 ? Room.to_sentence(m["other_names"]) : user["name"]
        directs.push(m)
      else
        m["display_name"] = m["room"]["name"]
        shared.push(m)
      end
    end
    @shared_memberships = shared
    @direct_memberships = directs
    @user = Present.user(user)
    @page_title = user["name"]
    @back_url = SessionTransfers.back_url(req)
    @platform = ApplicationPlatform.detect(req["headers"]["user-agent"])
    @transfer = SessionTransfers.link(req, user, user)
    @_render_page("users/profiles/show")
  end

  # PATCH /users/:user_id/profile
  # PUT /users/:user_id/profile
  def update
    attrs = permit(params["user"] ?? {}, {"name": true, "email_address": true, "password": true, "bio": true})
    changes = {}
    changes["name"] = attrs["name"] unless attrs["name"].nil?
    changes["email_address"] = User.normalize_email(attrs["email_address"]) unless attrs["email_address"].nil?
    changes["bio"] = attrs["bio"] unless attrs["bio"].nil?
    changes["password_digest"] = password_hash(attrs["password"]) unless attrs["password"].blank?
    if changes.keys.length > 0
      changes["updated_at"] = Clock.now
      # @user.update: a taken email address leaves the profile as it was.
      try
        Db.update_row("users", @_current_user_key, changes)
      catch error
        throw error unless str(error).contains("UNIQUE constraint failed")
      end
    end

    avatar = find_uploaded_file(req, "user[avatar]")
    Users.attach_avatar(@_current_user_key, avatar)
    @_flash("notice", avatar.nil? ? "✓" : "It may take up to 30 minutes to change everywhere.")
    redirect("/users/me/profile")
  end
end
