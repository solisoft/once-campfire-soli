# The "Notifications aren't allowed" help in rooms/involvements/_bell: the pwa/ partials for
# the visitor's browser and system. It depends on the user agent and the host only, so a
# cached page keyed by user agent can embed it as is.
class NotificationHelp
  # html, kept per worker for each user agent and host.
  static def cached_html(req, agent)
    name = "notification_help:" + Crypto.md5(agent + "|" + RoomPage.base_url(req))
    cached = PageCache.get(name)
    return cached unless cached.nil?

    html = NotificationHelp.html(req)
    PageCache.set(name, html)
    html
  end

  static def html(req)
    platform = ApplicationPlatform.detect(req["headers"]["user-agent"])
    locals = {"platform": platform, "root_url": RoomPage.base_url(req) + "/"}
    render_partial("pwa/browser_settings", locals) + render_partial("pwa/system_settings", locals) +
      render_partial("pwa/install_instructions", locals)
  end
end
