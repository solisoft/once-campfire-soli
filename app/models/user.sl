class User < Model
  static ROLES: Array = ["member", "administrator", "bot"]

  static def build_attributes(attrs)
    now = Clock.now
    {
      "name": attrs["name"], "email_address": User.normalize_email(attrs["email_address"]),
      "password_digest": attrs["password"].blank? ? nil : password_hash(attrs["password"]),
      "role": attrs["role"] ?? "member", "status": "active", "bio": attrs["bio"],
      "bot_token": attrs["bot_token"], "avatar": nil, "created_at": now, "updated_at": now
    }
  end

  static def normalize_email(email)
    email.nil? ? nil : email.trim.downcase
  end

  # User.create! plus after_create_commit :grant_membership_to_open_rooms
  static def create_user(attrs)
    user = Ids.create(User, User.build_attributes(attrs))
    return user if user._errors && user._errors.length > 0

    Membership.grant_open_rooms_to(user._key)
    user
  end

  static def find_hash(key)
    return nil if key.nil?

    k = str(key)
    rows = @sdbql{ FOR u IN users FILTER u._key == #{k} LIMIT 1 RETURN u }
    rows.is_a?("array") && rows.length > 0 ? rows[0] : nil
  end

  static def find_many(keys)
    return [] if keys.length == 0

    rows = @sdbql{ FOR u IN users FILTER u._key IN #{keys} RETURN u }
    rows.is_a?("array") ? rows : []
  end

  static def active_ordered
    rows = @sdbql{ FOR u IN users FILTER u.status == "active" SORT LOWER(u.name), u._key RETURN u }
    rows.is_a?("array") ? rows : []
  end

  static def active_without_bots_ordered
    rows = @sdbql{ FOR u IN users FILTER u.status == "active" AND u.role != "bot" SORT LOWER(u.name), u._key RETURN u }
    rows.is_a?("array") ? rows : []
  end

  static def any?
    rows = @sdbql{ FOR u IN users LIMIT 1 RETURN 1 }
    rows.is_a?("array") && rows.length > 0
  end

  static def authenticate_by(email, password)
    return nil if email.blank? || password.blank?

    e = User.normalize_email(email)
    rows = @sdbql{ FOR u IN users FILTER u.email_address == #{e} AND u.status == "active" LIMIT 1 RETURN u }
    return nil unless rows.is_a?("array") && rows.length > 0

    user = rows[0]
    return nil if user["password_digest"].nil?

    password_verify(password, user["password_digest"]) ? user : nil
  end

  static def first_administrator
    rows = @sdbql{ FOR u IN users FILTER u.role == "administrator" SORT u._key LIMIT 1 RETURN u }
    rows.is_a?("array") && rows.length > 0 ? rows[0] : nil
  end

  static def touch(key)
    User.update(key, {"updated_at": Clock.now})
  end

  # --- presentation ---------------------------------------------------------------------

  static def initials(user)
    words = Regex.find_all("\\b\\w", user["name"].to_s)
    words.map { |m| m["match"] }.join("")
  end

  static def title(user)
    [user["name"], user["bio"]].filter { |p| !p.blank? }.join(" – ")
  end

  static def administrator?(user)
    user != nil && user["role"] == "administrator"
  end

  static def bot?(user)
    user != nil && user["role"] == "bot"
  end

  # User::Role#can_administer?
  static def can_administer?(user, record = nil)
    return true if User.administrator?(user)
    return false if record.nil?
    return true if record["_key"].nil?

    record["creator_id"] == user["_key"]
  end

  # --- signed ids -------------------------------------------------------------------------

  static def avatar_token(user)
    Signer.generate(user["_key"], "avatar")
  end

  static def from_avatar_token(token)
    User.find_hash(Signer.verify(token, "avatar"))
  end

  static TRANSFER_EXPIRY_MS: Int = 14400000

  static def transfer_id(user)
    Signer.generate(user["_key"], "transfer", User.TRANSFER_EXPIRY_MS)
  end

  static def find_by_transfer_id(id)
    User.find_hash(Signer.verify(id, "transfer"))
  end

  # The signed global id an Action Text attachment carries for a mention.
  static def attachable_sgid(user)
    Signer.generate("gid://campfire/User/" + user["_key"], "attachable")
  end

  static def from_attachable_sgid(sgid)
    gid = Signer.verify(sgid, "attachable")
    return nil if gid.nil? || !gid.starts_with("gid://campfire/User/")

    User.find_hash(gid.replace("gid://campfire/User/", ""))
  end

  # --- bots -------------------------------------------------------------------------------

  static def generate_bot_token
    chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    token = ""
    for i in 0..12
      token += chars[Crypto.random_bytes(1)[0] % 62]
    end
    token
  end

  static def bot_key(user)
    user["_key"] + "-" + user["bot_token"].to_s
  end

  # The key is "<id>-<token>"; ids contain dashes, the token never does.
  static def authenticate_bot(bot_key)
    return nil if bot_key.blank?

    parts = bot_key.trim.split("-")
    return nil if parts.length < 2

    token = parts.last
    id = parts.take(parts.length - 1).join("-")
    user = User.find_hash(id)
    return nil if user.nil? || user["role"] != "bot" || user["status"] != "active"
    return nil if user["bot_token"].blank? || !Crypto.secure_compare(user["bot_token"], token)

    user
  end
end
