# Action Text for Lexxy bodies: rendering a stored body for display (attachments, then the
# ContentFilters, Action Text's sanitizer and auto_link), its plain text, and the body the
# editor gets back.
#
# Bodies are stored as Lexxy/Action Text sends them: HTML whose attachments are
# <action-text-attachment> elements — mentions (sgid → user) and Open Graph embeds.
class RichText
  static MENTION_TYPE: String = "application/vnd.campfire.mention"
  static OPENGRAPH_TYPE: String = "application/vnd.actiontext.opengraph-embed"
  static TOKEN: String = "<!--[\\s\\S]*?-->|<[a-zA-Z/!][^\"'>]*(?:\"[^\"]*\"[^\"'>]*|'[^']*'[^\"'>]*)*>|[^<]+|<"

  # SanitizeTags::ALLOWED_TAGS, as Action Text's and auto_link's sanitizers leave them.
  static ALLOWED_TAGS: Array = [
    "a", "abbr", "acronym", "address", "b", "big", "blockquote", "br", "cite", "code", "dd", "del", "dfn",
    "div", "dl", "dt", "em", "h1", "h2", "h3", "h4", "h5", "h6", "hr", "i", "ins", "kbd", "li", "ol", "p",
    "pre", "samp", "small", "span", "strong", "sub", "sup", "time", "tt", "ul", "var",
    "s", "u", "mark", "table", "thead", "tbody", "tfoot", "tr", "th", "td", "img"
  ]
  static ALLOWED_ATTRIBUTES: Array = [
    "href", "src", "width", "height", "alt", "cite", "datetime", "title", "class", "name", "abbr",
    "data-language", "lang"
  ]
  static VOID_TAGS: Array = ["br", "hr", "img", "input", "meta", "link", "source", "wbr"]
  # Removed with everything inside them (SanitizeTags replaces the node).
  static DROPPED_TAGS: Array = ["script", "style", "iframe", "object", "embed", "template", "noscript", "svg", "math", "form", "textarea", "select", "button", "title", "head"]
  static BLOCK_TAGS: Array = ["p", "div", "li", "blockquote", "pre", "h1", "h2", "h3", "h4", "h5", "h6", "tr", "figure", "figcaption", "dt", "dd", "table", "ul", "ol"]

  # --- parsing ----------------------------------------------------------------------------

  static def tokens(html)
    Regex.find_all(RichText.TOKEN, html ?? "").map { |m| m["match"] }
  end

  static def tag_name(token)
    m = Regex.capture("^</?\\s*(?P<name>[a-zA-Z][a-zA-Z0-9-]*)", token)
    m.nil? ? nil : m["name"].downcase
  end

  static def attributes(token)
    m = Regex.capture("^<[a-zA-Z][a-zA-Z0-9-]*(?P<rest>[\\s\\S]*?)/?>$", token)
    attrs = {}
    return attrs if m.nil?

    for a in Regex.find_all("[a-zA-Z_:][-a-zA-Z0-9_:.]*(?:\\s*=\\s*(?:\"[^\"]*\"|'[^']*'|[^\\s\"'=<>`]+))?", m["rest"])
      parts = Regex.capture("^(?P<name>[a-zA-Z_:][-a-zA-Z0-9_:.]*)(?:\\s*=\\s*(?:\"(?P<dq>[^\"]*)\"|'(?P<sq>[^']*)'|(?P<bare>[^\\s\"'=<>`]+)))?$", a["match"])
      next if parts.nil?

      value = parts["dq"] ?? parts["sq"] ?? parts["bare"] ?? ""
      attrs[parts["name"].downcase] = html_unescape(value)
    end
    attrs
  end

  static def closing?(token)
    token.starts_with("</")
  end

  static def tag?(token)
    token.length > 1 && token.starts_with("<") && !token.starts_with("<!--") && !RichText.tag_name(token).nil?
  end

  static def attachment_open?(token)
    RichText.tag?(token) && !RichText.closing?(token) && RichText.tag_name(token) == "action-text-attachment"
  end

  static def attachment_close?(token)
    RichText.closing?(token) && RichText.tag_name(token) == "action-text-attachment"
  end

  # --- display ----------------------------------------------------------------------------

  # message_presentation for a text message.
  static def render(body)
    html = RichText.render_attachments(body ?? "")
    html = RichText.remove_solo_unfurled_link_text(html, body ?? "")
    html = RichText.sanitize(html)
    html = RichText.auto_link(html)
    "<div class=\"lexxy-content\">\n  " + html + "\n</div>\n"
  end

  # Action Text attachments, rendered with their partials.
  static def render_attachments(body)
    out = ""
    tokens = RichText.tokens(body)
    i = 0
    while i < tokens.length
      t = tokens[i]
      if RichText.attachment_open?(t)
        attrs = RichText.attributes(t)
        i += 1
        while i < tokens.length && !RichText.attachment_close?(tokens[i])
          i += 1
        end
        out += RichText.render_attachment(attrs)
      else
        out += t
      end
      i += 1
    end
    out
  end

  static def render_attachment(attrs)
    content_type = attrs["content-type"] ?? ""
    if content_type.contains(RichText.OPENGRAPH_TYPE)
      embed = Opengraph.embed_from_attributes(attrs)
      return embed.nil? ? "" : Opengraph.embed_html(embed)
    end
    user = RichText.user_from_sgid(attrs["sgid"])
    return "" if user.nil?

    RichText.mention_html(Present.user(user))
  end

  # users/_mention.html.erb as Action Text's sanitizer leaves it.
  static def mention_html(user)
    "<span class=\"mention\"><a title=\"" + html_escape(user["title"]) + "\" class=\"btn avatar\" href=\"/users/" + user["_key"] +
      "\"><img src=\"" + html_escape(user["avatar_path"]) + "\" width=\"48\" height=\"48\"></a> " + html_escape(user["name"]) + "</span>"
  end

  # A signed global id: ours, or a Rails one, read without its signature for users only
  # (lib/rails_ext/action_text_attachables.rb lets mentions survive a rotated secret).
  static def user_from_sgid(sgid)
    return nil if sgid.blank?

    user = User.from_attachable_sgid(sgid)
    return user unless user.nil?

    data = sgid.split("--")[0]
    decoded = Base64.decode(data) rescue nil
    decoded = Base64.urlsafe_decode(data) rescue nil unless decoded.is_a?("string")
    return nil unless decoded.is_a?("string")

    m = Regex.capture("gid://campfire/User/(?P<id>[0-9A-Za-z-]+)", decoded)
    m.nil? ? nil : User.find_hash(m["id"])
  end

  # Allowed tags keep their allowed attributes; dropped tags vanish with their content;
  # any other tag vanishes but keeps its content.
  static def sanitize(html)
    out = ""
    dropping = nil
    depth = 0
    for t in RichText.tokens(html)
      unless dropping.nil?
        if RichText.tag?(t) && RichText.tag_name(t) == dropping
          depth += RichText.closing?(t) ? -1 : 1
          dropping = nil if depth == 0
        end
        next
      end
      next if t.starts_with("<!--")

      unless RichText.tag?(t)
        out += t == "<" ? "&lt;" : t
        next
      end

      name = RichText.tag_name(t)
      if RichText.DROPPED_TAGS.include?(name)
        unless RichText.closing?(t) || t.ends_with("/>")
          dropping = name
          depth = 1
        end
        next
      end
      next unless RichText.ALLOWED_TAGS.include?(name)

      if RichText.closing?(t)
        out += "</" + name + ">" unless RichText.VOID_TAGS.include?(name)
      else
        out += "<" + name + RichText.safe_attributes(RichText.attributes(t)) + ">"
      end
    end
    out
  end

  static def safe_attributes(attrs)
    out = ""
    attrs.each do |name, value|
      next unless RichText.ALLOWED_ATTRIBUTES.include?(name)
      next if (name == "href" || name == "src" || name == "cite") && !RichText.safe_url?(value)

      out += " " + name + "=\"" + html_escape(value) + "\""
    end
    out
  end

  static def safe_url?(url)
    v = Regex.replace_all("[\\x00-\\x20]", url.downcase, "")
    m = Regex.capture("^(?P<scheme>[a-z][a-z0-9+.-]*):", v)
    m.nil? || ["http", "https", "mailto", "tel", "ftp"].include?(m["scheme"])
  end

  # rails_autolink over the text outside links: http(s) and www. URLs, target="_blank".
  static def auto_link(html)
    out = ""
    in_link = 0
    for t in RichText.tokens(html)
      if RichText.tag?(t)
        in_link += RichText.closing?(t) ? -1 : 1 if RichText.tag_name(t) == "a"
        out += t
      elsif in_link > 0
        out += t
      else
        out += RichText.link_text(t)
      end
    end
    out
  end

  # The text between URLs comes from Regex.split and the URLs from find_all, so no offsets
  # are needed (find_all's are bytes, substring's are characters).
  static def link_text(text)
    return text unless text.contains("http") || text.contains("www.")

    pattern = "(?:https?://|www\\.)[^\\s<]+"
    urls = Regex.find_all(pattern, text).map { |m| m["match"] }
    return text if urls.length == 0

    between = Regex.split(pattern, text)
    out = between[0]
    for url, i in urls
      trimmed = Regex.replace("[.,;:!?'\"]+$", url, "")
      while trimmed.ends_with(")") && trimmed.split(")").length > trimmed.split("(").length
        trimmed = trimmed.substring(0, trimmed.chars().length - 1)
      end
      href = trimmed.starts_with("www.") ? "http://" + trimmed : trimmed
      rest = url.substring(trimmed.chars().length, url.chars().length)
      out += "<a target=\"_blank\" href=\"" + href + "\">" + trimmed + "</a>" + rest + (i + 1 < between.length ? between[i + 1] : "")
    end
    out
  end

  # ContentFilters::RemoveSoloUnfurledLinkText: a message that is only the link it unfurled
  # shows just the preview.
  static def remove_solo_unfurled_link_text(html, body)
    tokens = RichText.tokens(body)
    embeds = tokens.filter { |t| RichText.attachment_open?(t) && (RichText.attributes(t)["content-type"] ?? "").contains(RichText.OPENGRAPH_TYPE) }
    return html unless embeds.length == 1

    embed = Opengraph.embed_from_attributes(RichText.attributes(embeds[0]))
    return html if embed.nil? || embed["href"].nil?
    return html unless Opengraph.normalize_tweet_url(embed["href"]) == Opengraph.normalize_tweet_url(RichText.plain_text(body))

    divs = tokens.filter { |t| RichText.tag?(t) && !RichText.closing?(t) && RichText.tag_name(t) == "div" }
    if divs.length > 0
      return "<div>\n  " + Opengraph.embed_html(embed) + "\n</div>"
    end

    RichText.drop_paragraphs_without(html, "og-embed")
  end

  # Every <p>…</p> that doesn't contain marker is removed.
  static def drop_paragraphs_without(html, marker)
    out = ""
    paragraph = nil
    for t in RichText.tokens(html)
      if paragraph.nil?
        if RichText.tag?(t) && !RichText.closing?(t) && RichText.tag_name(t) == "p"
          paragraph = t
        else
          out += t
        end
      else
        paragraph += t
        if RichText.closing?(t) && RichText.tag_name(t) == "p"
          out += paragraph if paragraph.contains(marker)
          paragraph = nil
        end
      end
    end
    out + (paragraph ?? "")
  end

  # Message::Mentionee: the users a body mentions.
  static def mentioned_user_keys(body)
    keys = []
    for t in RichText.tokens(body ?? "")
      next unless RichText.attachment_open?(t)

      attrs = RichText.attributes(t)
      next if (attrs["content-type"] ?? "").contains(RichText.OPENGRAPH_TYPE)

      user = RichText.user_from_sgid(attrs["sgid"])
      keys.push(user["_key"]) unless user.nil?
    end
    keys.uniq
  end

  # --- plain text ------------------------------------------------------------------------

  # ActionText::Content#to_plain_text (mentions as "@Name", previews as nothing).
  static def plain_text(body)
    return "" if body.nil?

    out = ""
    tokens = RichText.tokens(body)
    i = 0
    while i < tokens.length
      t = tokens[i]
      if RichText.attachment_open?(t)
        attrs = RichText.attributes(t)
        unless (attrs["content-type"] ?? "").contains(RichText.OPENGRAPH_TYPE)
          user = RichText.user_from_sgid(attrs["sgid"])
          out += "@" + user["name"] unless user.nil?
        end
        i += 1
        while i < tokens.length && !RichText.attachment_close?(tokens[i])
          i += 1
        end
      elsif RichText.tag?(t)
        name = RichText.tag_name(t)
        if name == "br"
          out += "\n"
        elsif RichText.closing?(t) && RichText.BLOCK_TAGS.include?(name)
          out += "\n"
        elsif name == "li" && !RichText.closing?(t)
          out += "• "
        end
      elsif !t.starts_with("<!--")
        out += html_unescape(t)
      end
      i += 1
    end
    Regex.replace_all("\\n{3,}", out, "\n\n").trim
  end

  # --- editing ---------------------------------------------------------------------------

  # RichTextHelper#editable_body: every attachment rebuilt from its attachable, with the
  # content the editor displays.
  static def editable(body)
    out = ""
    tokens = RichText.tokens(body ?? "")
    i = 0
    while i < tokens.length
      t = tokens[i]
      if RichText.attachment_open?(t)
        attrs = RichText.attributes(t)
        i += 1
        while i < tokens.length && !RichText.attachment_close?(tokens[i])
          i += 1
        end
        if (attrs["content-type"] ?? "").contains(RichText.OPENGRAPH_TYPE)
          embed = Opengraph.embed_from_attributes(attrs)
          out += RichText.attachment_tag(nil, RichText.OPENGRAPH_TYPE, Opengraph.embed_markup(embed)) unless embed.nil?
        else
          user = RichText.user_from_sgid(attrs["sgid"])
          unless user.nil?
            presented = Present.user(user)
            sgid = User.attachable_sgid(user)
            content = "<span class=\"mention\" sgid=\"" + sgid + "\">" + RichText.mention_avatar(presented) + " " + html_escape(user["name"]) + "</span>"
            out += RichText.attachment_tag(sgid, RichText.MENTION_TYPE, content)
          end
        end
      else
        out += t
      end
      i += 1
    end
    out
  end

  static def attachment_tag(sgid, content_type, content)
    sgid_attr = sgid.nil? ? "" : " sgid=\"" + sgid + "\""
    "<action-text-attachment" + sgid_attr + " content-type=\"" + content_type + "\" content=\"" + html_escape(content) + "\"></action-text-attachment>"
  end

  static def mention_avatar(user)
    "<a title=\"" + html_escape(user["title"]) + "\" class=\"btn avatar\" data-turbo-frame=\"_top\" href=\"/users/" + user["_key"] +
      "\"><img aria-hidden=\"true\" src=\"" + html_escape(user["avatar_path"]) + "\" width=\"48\" height=\"48\" /></a>"
  end
end
