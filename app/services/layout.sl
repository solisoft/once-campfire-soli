# What layouts/application.html.erb reads from Current and the helpers.
class Layout
  static def data(req)
    user = req["current_user"]
    account = req["account"]
    classes = []
    classes.push("admin") if !user.nil? && User.can_administer?(user)
    classes.push("account-has-logo") if !account.nil? && !account["logo"].nil?
    {
      "user": user.nil? ? nil : Present.user(user),
      "account": account,
      "logo_path": Present.logo_path(account),
      "custom_styles": account.nil? ? nil : account["custom_styles"],
      "vapid_public_key": getenv("VAPID_PUBLIC_KEY") ?? "",
      "admin_and_logo_classes": classes.join(" ")
    }
  end
end
