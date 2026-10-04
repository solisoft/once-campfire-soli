class AutocompletableUsersController < ApplicationController
  static PER_PAGE: Int = 20

  # GET /autocompletable/users — <lexxy-prompt-item>s for the mentions prompt, or JSON for the
  # autocomplete inputs. The editor filters with `filter`, the inputs with `query`.
  def index
    room_key = nil
    unless params["room_id"].blank?
      found = Membership.with_room_for(@_current_user_key, params["room_id"])
      halt(404, "") if found.nil?

      room_key = found["room"]["_key"]
    end
    query = params["filter"].blank? ? params["query"] : params["filter"]
    page = int(params["page"] ?? "1") rescue 1
    page = 1 if page < 1
    per_page = AutocompletableUsersController.PER_PAGE
    users = Present.users(User.autocompletable(room_key, query.blank? ? nil : query, (page - 1) * per_page, per_page))

    if @_json_requested?
      headers = {"Content-Type": "application/json; charset=utf-8"}
      return {"status": 200, "headers": headers, "body": json_stringify(@_json_users(users))}
    end

    for u in users
      u["sgid"] = User.attachable_sgid(u)
    end
    @users = users
    render("autocompletable/users/index", {}, {"layout": false})
  end

  private

  # autocompletable/users/_user.json.jbuilder
  def _json_users(users)
    base = RoomPage.base_url(req)
    users.map { |u|
      {"name": html_escape(u["name"]), "value": int(u["_key"]), "avatar_url": base + u["avatar_path"],
       "sgid": User.attachable_sgid(u)}
    }
  end

  # respond_to: JSON when the Accept header asks for it ahead of HTML.
  def _json_requested?
    accept = req["headers"]["accept"].to_s
    return false unless accept.contains("application/json")
    return true unless accept.contains("text/html")

    accept.split("application/json")[0].length < accept.split("text/html")[0].length
  end
end
