class Emoji
  # String#all_emoji? (lib/rails_ext/string.rb)
  static def all_emoji?(text)
    return false if text.blank?

    Regex.matches("^(\\p{Emoji_Presentation}|\\p{Extended_Pictographic}|\\x{FE0F})+$", text)
  end
end
