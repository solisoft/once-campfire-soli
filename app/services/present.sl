# Decorates rows with what views compute in the reference from model methods and route
# helpers: views here can call helper functions but not models or services.
class Present
  # fresh_user_avatar_path plus User#title, #initials and role predicates.
  static def user(user)
    return nil if user.nil?

    user["avatar_path"] = "/users/" + User.avatar_token(user) + "/avatar?v=" + str(user["updated_at"])
    user["title"] = User.title(user)
    user["administrator"] = user["role"] == "administrator"
    user["bot"] = user["role"] == "bot"
    user
  end

  static def users(users)
    users.map { |u| Present.user(u) }
  end

  # fresh_account_logo_path
  static def logo_path(account, size = nil)
    v = account.nil? ? "" : str(account["updated_at"])
    path = "/account/logo?v=" + v
    size.nil? ? path : path + "&size=" + size
  end
end
