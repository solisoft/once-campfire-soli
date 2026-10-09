class UsersAvatarsController < ApplicationController
  static AVATAR_COLORS: Array = ["#AF2E1B", "#CC6324", "#3B4B59", "#BFA07A", "#ED8008", "#ED3F1C", "#BF1B1B", "#736B1E", "#D07B53",
                   "#736356", "#AD1D1D", "#BF7C2A", "#C09C6F", "#698F9C", "#7C956B", "#5D618F", "#3B3633", "#67695E"]

  # GET /users/:user_id/avatar — the user's square variant, the bot default, or initials.
  def show
    user = User.from_avatar_token(req["params"]["user_id"])
    return @_head(404) if user.nil?

    etag = "W/\"" + user["_key"] + "-" + str(user["updated_at"]) + "\""
    return @_head(304, {"ETag": etag}) if req["headers"]["if-none-match"] == etag

    cache = {"Cache-Control": "max-age=1800, public, stale-while-revalidate=604800", "ETag": etag}
    avatar = user["avatar"]
    if !avatar.nil? && !avatar["square_blob_id"].nil?
      cache["Content-Type"] = "image/webp"
      cache["Content-Disposition"] = "inline"
      return Attachments.response(avatar["square_blob_id"], req, cache)
    end
    if user["role"] == "bot"
      cache["Content-Type"] = "image/svg+xml"
      return {"status": 200, "headers": cache, "body": slurp("reference/app/assets/images/default-bot-avatar.svg")}
    end

    cache["Content-Type"] = "image/svg+xml"
    {"status": 200, "headers": cache, "body": UsersAvatarsController.initials_svg(user)}
  end

  # DELETE /users/:user_id/avatar
  def destroy
    Users.remove_avatar(@_current_user_key)
    redirect("/users/me/profile")
  end

  # users/avatars/show.svg.erb, colored by Zlib.crc32(user.to_param).
  static def initials_svg(user)
    initials = User.initials(user)
    color = UsersAvatarsController.AVATAR_COLORS[Crc32.of(user["_key"]) % UsersAvatarsController.AVATAR_COLORS.length]
    length = initials.chars().length >= 3 ? "textLength=\"85%\" lengthAdjust=\"spacingAndGlyphs\"" : ""
    "<svg version=\"1.1\" xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\"\n  viewBox=\"0 0 512 512\" class=\"avatar\" aria-hidden=\"true\">\n  <defs>\n    <clipPath id=\"porthole\">\n      <circle cx=\"50%\" cy=\"50%\" r=\"50%\" />\n    </clipPath>\n  </defs>\n\n  <g>\n    <rect width=\"100%\" height=\"100%\" rx=\"50\" fill=\"" +
      color + "\" />\n\n    <text x=\"50%\" y=\"50%\" fill=\"#FFFFFF\"\n      text-anchor=\"middle\" dy=\"0.35em\"\n      " + length +
      "\n      font-family=\"-apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Helvetica, Arial, sans-serif\"\n      font-size=\"230\"\n      font-weight=\"800\"\n      letter-spacing=\"-5\">\n      " +
      html_escape(initials) + "\n    </text>\n  </g>\n</svg>\n"
  end
end
