# Opengraph::Metadata.from_url with Opengraph::Location, ::Fetch and ::Document: a page's
# og:title, og:url, og:image and og:description, for the composer's link previews.
#
# Server-side request forgery is kept out twice over: Soli's HTTP client refuses loopback,
# private and link-local addresses (checked again on the resolved address and on every
# redirect, which are followed here one by one), and only http(s) URLs are ever fetched.
class OpengraphMetadata
  static ATTRIBUTES: Array = ["title", "url", "image", "description"]
  static MAX_BODY_SIZE: Int = 5242880
  static MAX_REDIRECTS: Int = 10
  static TIMEOUT_SECONDS: Int = 10
  static FX_TWITTER_HOST: String = "fxtwitter.com"
  static ALLOWED_IMAGE_CONTENT_TYPES: Array = ["image/jpeg", "image/png", "image/gif", "image/webp"]
  static FILES_AND_MEDIA_URL: String = "\\bhttps?://\\S+\\.(?:zip|tar|tar\\.gz|tar\\.bz2|tar\\.xz|gz|bz2|rar|7z|dmg|exe|msi|pkg|deb|iso|jpg|jpeg|png|gif|bmp|mp4|mov|avi|mkv|wmv|flv|heic|heif|mp3|wav|ogg|aac|wma|webm|ogv|mpg|mpeg)\\b"

  # The metadata, or nil when it isn't valid (title, url and description present, the image
  # a public URL).
  static def from_url(untrusted_url)
    html = OpengraphMetadata.fetch_document(untrusted_url)
    attrs = OpengraphMetadata.attributes_of(html)
    title = OpengraphMetadata.sanitize(attrs["title"])
    description = OpengraphMetadata.sanitize(attrs["description"])
    url = OpengraphMetadata.valid_location?(attrs["url"]) ? attrs["url"] : untrusted_url
    image = OpengraphMetadata.valid_image(attrs["image"])
    return nil if title.blank? || url.blank? || description.blank?
    return nil if !image.blank? && !OpengraphMetadata.valid_location?(image)

    {"title": title, "url": url, "image": image, "description": description}
  end

  # --- Opengraph::Location ----------------------------------------------------------------

  static def parse(url)
    return nil if url.blank?

    Regex.capture("^(?P<scheme>[hH][tT][tT][pP][sS]?)://(?:[^@/?#]*@)?(?P<host>\\[[^\\]]+\\]|[^:/?#]+)(?::(?P<port>[0-9]+))?(?P<path>[^?#]*)", url.trim)
  end

  # A public http(s) URL: Soli's client will refuse the rest when it is fetched, so this
  # only screens out what is plainly not one.
  static def valid_location?(url)
    parsed = OpengraphMetadata.parse(url)
    return false if parsed.nil?

    host = parsed["host"].downcase
    return false if host == "localhost" || host.ends_with(".localhost") || host.starts_with("[")

    !Regex.matches("^(127\\.|10\\.|0\\.|169\\.254\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.)", host)
  end

  # --- Opengraph::Metadata::Fetching ------------------------------------------------------

  static def fetch_document(untrusted_url)
    url = untrusted_url
    url = OpengraphMetadata.fxtwitter_url(url) if OpengraphMetadata.tweet_url?(url)
    return nil if url.nil? || !OpengraphMetadata.valid_location?(url)
    return nil if Regex.matches(OpengraphMetadata.FILES_AND_MEDIA_URL, url)

    response = OpengraphMetadata.request("GET", url)
    return nil if response.nil? || response["status"] != 200
    return nil unless OpengraphMetadata.header(response, "content-type").split(";")[0].trim.downcase == "text/html"

    length = OpengraphMetadata.header(response, "content-length")
    return nil if !length.blank? && length.to_i > OpengraphMetadata.MAX_BODY_SIZE

    body = response["body"] ?? ""
    body.length > OpengraphMetadata.MAX_BODY_SIZE ? nil : body
  end

  static def valid_image(image)
    return nil if image.blank? || !OpengraphMetadata.valid_location?(image)

    response = OpengraphMetadata.request("HEAD", image)
    return nil if response.nil?

    content_type = OpengraphMetadata.header(response, "content-type").split(";")[0].trim.downcase
    OpengraphMetadata.ALLOWED_IMAGE_CONTENT_TYPES.include?(content_type) ? image : nil
  end

  # Opengraph::Fetch#request: redirects followed by hand, each hop checked again.
  static def request(method, url)
    current = url
    for hop in 0..OpengraphMetadata.MAX_REDIRECTS
      response = nil
      try
        response = HTTP.request(method, current, {"timeout": OpengraphMetadata.TIMEOUT_SECONDS, "Accept": "text/html,*/*"})
      catch error
        print("[opengraph] failed to fetch " + current + " (" + str(error) + ")")
        return nil
      end
      status = response["status"] ?? 0
      return response unless status >= 300 && status < 400

      location = OpengraphMetadata.header(response, "location")
      return nil if location.blank?

      current = OpengraphMetadata.resolve(current, location)
      return nil unless OpengraphMetadata.valid_location?(current)
    end
    nil
  end

  static def resolve(base, location)
    return location if Regex.matches("^[hH][tT][tT][pP][sS]?://", location)

    parsed = OpengraphMetadata.parse(base)
    return location if parsed.nil?

    origin = parsed["scheme"] + "://" + parsed["host"] + (parsed["port"].blank? ? "" : ":" + parsed["port"])
    return parsed["scheme"] + ":" + location if location.starts_with("//")
    return origin + location if location.starts_with("/")

    dir = parsed["path"].contains("/") ? parsed["path"].split("/").take(parsed["path"].split("/").length - 1).join("/") : ""
    origin + dir + "/" + location
  end

  static def header(response, name)
    value = ""
    (response["headers"] ?? {}).each do |k, v|
      value = str(v) if k.downcase == name
    end
    value
  end

  # Twitter.com and X.com don't serve Open Graph; fxtwitter.com does for them.
  static def tweet_url?(url)
    parsed = OpengraphMetadata.parse(url)
    return false if parsed.nil?

    Opengraph.TWITTER_HOSTS.include?(parsed["host"].downcase) && !parsed["path"].blank? && parsed["path"] != "/"
  end

  static def fxtwitter_url(url)
    parsed = OpengraphMetadata.parse(url)
    return nil if parsed.nil?

    rest = url.trim.substring(parsed["scheme"].length + 3 + parsed["host"].length, url.trim.length)
    parsed["scheme"] + "://" + OpengraphMetadata.FX_TWITTER_HOST + rest
  end

  # --- Opengraph::Document ----------------------------------------------------------------

  # <meta property="og:…" content="…"> (or name="og:…"), the last of each kept.
  static def attributes_of(html)
    attrs = {}
    return attrs if html.nil?

    for m in Regex.find_all("<meta\\b[^>]*>", html)
      tag_attrs = RichText.attributes(m["match"])
      key = tag_attrs["property"] ?? tag_attrs["name"]
      next if key.nil? || !key.starts_with("og:")

      name = key.replace("og:", "")
      content = tag_attrs["content"]
      attrs[name] = content if OpengraphMetadata.ATTRIBUTES.include?(name) && !content.blank?
    end
    attrs
  end

  # sanitize(strip_tags(value)): the text, with &, < and > escaped as the full sanitizer leaves them.
  static def sanitize(value)
    return nil if value.nil?

    text = strip_html(value)
    text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
  end
end
