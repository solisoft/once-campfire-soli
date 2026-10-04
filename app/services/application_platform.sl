# ApplicationPlatform (PlatformAgent over the useragent gem), reduced to what the views ask:
# a hash of the predicates, the browser name and the operating system.
class ApplicationPlatform
  static def detect(user_agent)
    ua = user_agent.to_s
    browser = ApplicationPlatform.browser(ua)
    ios = Regex.matches("iPhone|iPad", ua)
    android = Regex.matches("Android", ua)
    {
      "browser": browser,
      "chrome": Regex.matches("Chrome", browser),
      "firefox": Regex.matches("Firefox|FxiOS", browser),
      "safari": Regex.matches("Safari", browser),
      "edge": Regex.matches("Edg", browser),
      "ios": ios,
      "android": android,
      "mac": Regex.matches("Macintosh", ua),
      "mobile": ios || android,
      "desktop": !(ios || android),
      "operating_system": ApplicationPlatform.operating_system(ua)
    }
  end

  # UserAgent::Browsers: the first family that claims the agent, in the gem's order.
  static def browser(ua)
    # The useragent gem knows only legacy Edge (a last product of "Edge/"); Chromium Edge
    # ("Edg/") reads as Chrome, so the reference does too.
    return "Edge" if Regex.matches("Edge/", ua)
    return "Opera" if Regex.matches("OPR/|Opera", ua)
    return "Vivaldi" if Regex.matches("Vivaldi/", ua)
    return "Chrome" if Regex.matches("Chrome/|CriOS/", ua)
    return "Safari" if Regex.matches("AppleWebKit/", ua)
    return "Firefox" if Regex.matches("Firefox/", ua)
    return "" if ua.blank?

    ua.split(" ")[0].to_s.split("/")[0].to_s
  end

  static def operating_system(ua)
    return "Android" if Regex.matches("Android", ua)
    return "iPad" if Regex.matches("iPad", ua)
    return "iPhone" if Regex.matches("iPhone", ua)
    return "macOS" if Regex.matches("Macintosh", ua)
    return "Windows" if Regex.matches("Windows", ua)
    return "ChromeOS" if Regex.matches("CrOS", ua)
    return "Linux" if Regex.matches("Linux", ua)

    ""
  end

  # UserAgent.parse(user_agent): browser, version and platform, for the subscriptions list.
  static def describe(user_agent)
    ua = user_agent.to_s
    browser = ApplicationPlatform.browser(ua)
    {
      "browser": browser, "version": ApplicationPlatform.version(ua, browser),
      "platform": ApplicationPlatform.platform(ua)
    }
  end

  static def version(ua, browser)
    tokens = {"Edge": "Edge", "Opera": "OPR", "Vivaldi": "Vivaldi", "Chrome": "(?:Chrome|CriOS)",
              "Safari": "Version", "Firefox": "Firefox"}
    token = tokens[browser]
    return "" if token.nil?

    m = Regex.capture(token + "/(?P<v>[0-9][0-9A-Za-z.]*)", ua)
    m.nil? ? "" : m["v"]
  end

  # The first comment of the agent: "Macintosh", "X11", "iPhone", "Windows"…
  static def platform(ua)
    m = Regex.capture("\\((?P<c>[^;)]*)", ua)
    return "" if m.nil?

    first = m["c"].trim
    return "Windows" if first.starts_with("Windows")
    return "ChromeOS" if Regex.matches("CrOS", ua)
    return "Android" if Regex.matches("Android", ua) && first == "Linux"

    first
  end
end
