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

  # User.create! plus after_create_commit :grant_membership_to_open_rooms. nil when the email
  # address (or the bot token) is taken.
  static def create_user(attrs)
    user = User.insert(attrs)
    Membership.grant_open_rooms_to(user["_key"]) unless user.nil?
    user
  end

  static def insert(attrs)
    try
      return Ids.create("users", User.build_attributes(attrs))
    catch error
      throw error unless str(error).contains("UNIQUE constraint failed: users.")
    end
    nil
  end

  static def find_hash(key)
    return nil if key.nil?

    Db.find_row("users", key)
  end

  static def find_many(keys)
    return [] if keys.length == 0

    Db.rows("SELECT " + Db.json("users", "u") + " AS j FROM users u WHERE u._key IN (" + Db.marks(keys) + ")", keys)
  end

  static def active_ordered
    Db.rows("SELECT " + Db.json("users", "u") + " AS j FROM users u WHERE u.status = 'active' ORDER BY lower(u.name), u._key")
  end

  static def active_without_bots_ordered
    Db.rows("SELECT " + Db.json("users", "u") + " AS j FROM users u WHERE u.status = 'active' AND u.role != 'bot' ORDER BY lower(u.name), u._key")
  end

  static def any?
    Db.value("SELECT EXISTS (SELECT 1 FROM users) AS v") == 1
  end

  static def authenticate_by(email, password)
    return nil if email.blank? || password.blank?

    user = Db.row("SELECT " + Db.json("users", "u") + " AS j FROM users u WHERE u.email_address = ? AND u.status = 'active'",
                  [User.normalize_email(email)])
    return nil if user.nil? || user["password_digest"].nil?

    password_verify(password, user["password_digest"]) ? user : nil
  end

  static def first_administrator
    Db.row("SELECT " + Db.json("users", "u") + " AS j FROM users u WHERE u.role = 'administrator' ORDER BY u._key LIMIT 1")
  end

  static def touch(key)
    Db.update_row("users", key, {"updated_at": Clock.now})
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

  # User.active_bots.ordered
  static def active_bots_ordered
    Db.rows("SELECT " + Db.json("users", "u") + " AS j FROM users u WHERE u.status = 'active' AND u.role = 'bot' ORDER BY lower(u.name), u._key")
  end

  # User.active_bots.find
  static def find_active_bot(key)
    user = User.find_hash(key)
    return nil if user.nil? || user["role"] != "bot" || user["status"] != "active"

    user
  end

  # User.active.find
  static def find_active(key)
    user = User.find_hash(key)
    return nil if user.nil? || user["status"] != "active"

    user
  end

  # AccountsController#account_users.ordered.without_bots: administrators also see the banned.
  static def account_users_ordered(with_banned)
    statuses = with_banned ? "'active', 'banned'" : "'active'"
    Db.rows("SELECT " + Db.json("users", "u") + " AS j FROM users u WHERE u.status IN (" + statuses + ") AND u.role != 'bot' " +
            "ORDER BY lower(u.name), u._key")
  end

  # Autocompletable::UsersController: active users (of a room when room_key is given) whose
  # name contains query, ignoring case (SQLite's LIKE), ordered by name, one page of them.
  static def autocompletable(room_key, query, offset, limit)
    pattern = "%" + query.to_s + "%"
    if room_key.nil?
      return Db.rows("SELECT " + Db.json("users", "u") + " AS j FROM users u WHERE u.status = 'active' AND u.name LIKE ? " +
                     "ORDER BY lower(u.name), u._key LIMIT " + str(int(limit)) + " OFFSET " + str(int(offset)), [pattern])
    end

    Db.rows("SELECT " + Db.json("users", "u") + " AS j FROM memberships m JOIN users u ON u._key = m.user_id " +
            "WHERE m.room_id = ? AND u.status = 'active' AND u.name LIKE ? ORDER BY lower(u.name), u._key " +
            "LIMIT " + str(int(limit)) + " OFFSET " + str(int(offset)), [str(room_key), pattern])
  end

  static def set_role(key, role)
    Db.update_row("users", key, {"role": role, "updated_at": Clock.now})
  end

  # User::Bot#reset_bot_key
  static def reset_bot_key(key)
    Db.update_row("users", key, {"bot_token": User.generate_bot_token, "updated_at": Clock.now})
  end

  # User#deactivate: close the sockets, drop memberships (direct rooms excepted), push
  # subscriptions, searches and sessions, then mark the user deactivated under a freed email.
  static def deactivate(user)
    key = user["_key"]
    Cable.disconnect_user(key, false) rescue nil
    Membership.delete_for_user_without_direct_rooms(key)
    PushSubscription.destroy_for_user(key)
    Search.clear_for(key)
    Session.destroy_for_user(key)
    email = user["email_address"]
    email = email.replace("@", "-deactivated-" + uuid_v4() + "@") unless email.nil?
    Db.update_row("users", key, {"status": "deactivated", "email_address": email, "updated_at": Clock.now})
  end
end
