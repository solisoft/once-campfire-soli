# Signed, optionally expiring tokens, in the spirit of ActiveSupport::MessageVerifier:
# base64url(JSON) + "--" + HMAC-SHA256 over the payload, a purpose and SECRET_KEY_BASE.
# Used for the session cookie, signed ids (avatars, transfers, mentions) and stream names.
class Signer
  static def secret
    getenv("SECRET_KEY_BASE") ?? "insecure-development-secret"
  end

  static def generate(value, purpose, expires_in_ms = nil)
    payload = {"v": value}
    payload["e"] = Clock.now + expires_in_ms unless expires_in_ms.nil?
    data = Base64.urlsafe_encode(json_stringify(payload))
    data + "--" + Signer.digest(data, purpose)
  end

  static def verify(token, purpose)
    return nil if token.nil? || !token.is_a?("string")

    parts = token.split("--")
    return nil unless parts.length == 2

    data = parts[0]
    return nil unless Crypto.secure_compare(parts[1], Signer.digest(data, purpose))

    payload = JSON.parse(Base64.urlsafe_decode(data)) rescue nil
    return nil unless payload.is_a?("hash")
    return nil if !payload["e"].nil? && payload["e"] < Clock.now

    payload["v"]
  end

  static def digest(data, purpose)
    Crypto.hmac(purpose + ":" + data, Signer.secret, "sha256")
  end
end
