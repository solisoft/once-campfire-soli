# User operations that span several collections.
class Users
  static AVATAR_VARIANTS: Hash = {"square": {"size": 512, "format": "webp"}}

  static def attach_avatar(user_key, file)
    return nil if file.nil? || file["size"] == 0

    user = User.find_hash(user_key)
    Attachments.delete_image_set(user["avatar"]) unless user.nil?
    Db.update_row("users", user_key, {"avatar": Attachments.create_image_set(file, Users.AVATAR_VARIANTS), "updated_at": Clock.now})
  end

  static def remove_avatar(user_key)
    user = User.find_hash(user_key)
    return nil if user.nil? || user["avatar"].nil?

    Attachments.delete_image_set(user["avatar"])
    Db.update_row("users", user_key, {"avatar": nil, "updated_at": Clock.now})
  end
end
