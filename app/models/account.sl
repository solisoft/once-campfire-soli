# The single account (Account.first in the reference), stored under the _key "campfire".
class Account < Model
  static KEY: String = "campfire"

  static def current
    rows = @sdbql{ FOR a IN accounts FILTER a._key == "campfire" RETURN a }
    rows.is_a?("array") && rows.length > 0 ? rows[0] : nil
  end

  static def exists?
    Account.current != nil
  end

  static def create_singleton(name)
    now = Clock.now
    Account.create({
      "name": name, "join_code": Account.generate_join_code, "custom_styles": nil,
      "settings": {"restrict_room_creation_to_administrators": false},
      "logo": nil, "created_at": now, "updated_at": now
    }, {"key": Account.KEY})
  end

  static def generate_join_code
    chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    code = ""
    for i in 0..12
      code += "-" if i > 0 && i % 4 == 0
      code += chars[Crypto.random_bytes(1)[0] % 62]
    end
    code
  end

  static def update_fields(fields)
    fields["updated_at"] = Clock.now
    Account.update(Account.KEY, fields)
  end

  static def restrict_room_creation?(account)
    account.dig("settings", "restrict_room_creation_to_administrators") == true
  end
end
