# Open Graph link previews: the embeds stored in message bodies
# (ActionText::Attachment::OpengraphEmbed) and fetching a page's metadata (Opengraph::*).
class Opengraph
  static TWITTER_AVATAR_URL_PREFIX: String = "https://pbs.twimg.com/profile_images"
  static TWITTER_HOSTS: Array = ["twitter.com", "www.twitter.com", "x.com", "www.x.com"]

  # Trix stored the details as attributes; Lexxy stores them in the content markup.
  static def embed_from_attributes(attrs)
    embed = nil
    if !attrs["filename"].blank?
      embed = {"href": Opengraph.web_url(attrs["href"]), "url": Opengraph.web_url(attrs["url"]),
               "filename": attrs["filename"], "description": attrs["caption"]}
    else
      content = attrs["content"] ?? ""
      title = Opengraph.inner(content, "og-embed__title")
      link = Regex.capture("<a\\b[^>]*href=\"(?P<href>[^\"]*)\"[^>]*>(?P<text>[\\s\\S]*?)</a>", title ?? "")
      image = Regex.capture("<img\\b[^>]*src=\"(?P<src>[^\"]*)\"", Opengraph.inner(content, "og-embed__image") ?? "")
      filename = link.nil? ? title : link["text"]
      embed = {
        "href": Opengraph.web_url(link.nil? ? nil : html_unescape(link["href"])),
        "url": Opengraph.web_url(image.nil? ? nil : html_unescape(image["src"])),
        "filename": filename.nil? ? nil : html_unescape(strip_html(filename)).trim,
        "description": Opengraph.text_of(Opengraph.inner(content, "og-embed__description"))
      }
    end
    embed["filename"].blank? && embed["href"].nil? ? nil : embed
  end

  static def inner(html, class_name)
    m = Regex.capture("class=\"" + class_name + "\"[^>]*>(?P<inner>[\\s\\S]*?)</div>", html)
    m.nil? ? nil : m["inner"]
  end

  static def text_of(html)
    html.nil? ? nil : html_unescape(strip_html(html)).trim
  end

  # Only absolute http(s) URLs on a named host other than ours.
  static def web_url(value)
    return nil if value.blank?

    m = Regex.capture("^(?P<scheme>https?)://(?P<host>[^/:?#]+)", value)
    return nil if m.nil?

    host = m["host"].downcase
    return nil if host.contains("%") || !host.contains(".")

    last = host.split(".").last
    return nil unless Regex.matches("[a-z]", last) && !Regex.matches("^0x", last)

    value
  end

  # action_text/attachables/_opengraph_embed.html.erb
  static def embed_html(embed)
    twitter = (embed["url"] ?? "").starts_with(Opengraph.TWITTER_AVATAR_URL_PREFIX) ? "og-embed--twitter-avatar" : ""
    title = Opengraph.truncate(embed["filename"] ?? "", 280)
    link = embed["href"].blank? ? html_escape(title) : "<a rel=\"noreferrer\" target=\"_blank\" href=\"" + html_escape(embed["href"]) + "\">" + html_escape(title) + "</a>"
    image = embed["url"].nil? ? "" : "        <div class=\"og-embed__image\">\n          <img src=\"" + html_escape(embed["url"]) + "\" class=\"image center\" alt=\"\" />\n        </div>\n"
    "<figure class=\"attachment attachment--content attachment--og\">\n  <actiontext-opengraph-embed>\n    <div class=\"og-embed gap " + twitter + "\">\n" +
      "      <div class=\"og-embed__content\">\n        <div class=\"og-embed__title\">\n          " + link + "\n        </div>\n" +
      "        <div class=\"og-embed__description\">" + html_escape(Opengraph.truncate(embed["description"] ?? "", 560)) + "</div>\n      </div>\n" +
      image + "    </div>\n  </actiontext-opengraph-embed>\n</figure>\n"
  end

  # The content the editor keeps for an embed.
  static def embed_markup(embed)
    Opengraph.embed_html(embed)
  end

  static def truncate(text, length)
    chars = text.chars()
    return text if chars.length <= length

    chars.take(length - 1).join("") + "…"
  end

  static def normalize_tweet_url(url)
    return url if url.blank?

    stripped = url.trim
    twitter = stripped.contains("x.com") || stripped.contains("twitter.com")
    return url unless twitter

    m = Regex.capture("^(?P<scheme>https?)://(?P<host>[^/?#]+)(?P<path>[^?#]*)", stripped)
    return url if m.nil?

    host = m["host"].downcase == "x.com" ? "twitter.com" : m["host"]
    m["scheme"] + "://" + host + m["path"]
  end
end
