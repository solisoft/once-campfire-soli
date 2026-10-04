# pwa/manifest.json.erb and pwa/service_worker.js, served at stable root URLs.
class PwaAssets
  # The template's interpolations are ERB's, so they come out HTML-escaped (the logo URL's
  # "&amp;" included), exactly as the reference serves them.
  static def manifest(account, base_url)
    name = account.nil? || account["name"].blank? ? "Campfire" : account["name"]
    v = account.nil? ? "" : str(account["updated_at"])
    out = """{
  "name": "NAME",
  "icons": [
    {
      "src": "/account/logo?size=small&amp;v=VERSION",
      "type": "image/png",
      "sizes": "192x192"
    },
    {
      "src": "/account/logo?v=VERSION",
      "type": "image/png",
      "sizes": "512x512"
    },
    {
      "src": "/account/logo?v=VERSION",
      "type": "image/png",
      "sizes": "512x512",
      "purpose": "maskable"
    }
  ],
  "start_url": "/",
  "display": "standalone",
  "scope": "/",
  "description": "A chat app from the makers of Basecamp and HEY.",
  "categories": ["social", "business", "productivity"],
  "theme_color": "#ffffff",
  "background_color": "#ffffff",
  "shortcuts": [
    {
      "name": "New chat room",
      "description": "Open Campfire and start a new chat room",
      "url": "rooms/opens/new",
      "icons": [{ "src": "ADD_ICON", "sizes": "any" }]
    },
    {
      "name": "My profile",
      "description": "Open Campfire and view your profile",
      "url": "/users/me/profile",
      "icons": [{ "src": "PERSON_ICON", "sizes": "any" }]
    }
  ],
  "screenshots": [
    {
      "src": "CHAT_SCREENSHOT",
      "sizes": "1080x2400",
      "form_factor": "narrow",
      "label": "Campfire is an installable, self-hosted group chat system."
    },
    {
      "src": "SIDEBAR_SCREENSHOT",
      "sizes": "1080x2400",
      "form_factor": "narrow",
      "label": "Easily invite people. Make rooms. @mentions, DMs, and mobile support."
    },
    {
      "src": "DARK_SCREENSHOT",
      "sizes": "1080x2400",
      "form_factor": "narrow",
      "label": "Full support for dark mode, customizable to your brand."
    }
  ]
}
"""
    out = out.replace("NAME", html_escape(name)).replace("VERSION", v)
    out = out.replace("ADD_ICON", base_url + AssetManifest.path("add.svg")).replace("PERSON_ICON", base_url + AssetManifest.path("person.svg"))
    out = out.replace("CHAT_SCREENSHOT", base_url + AssetManifest.path("screenshots/android-chat.png"))
    out = out.replace("SIDEBAR_SCREENSHOT", base_url + AssetManifest.path("screenshots/android-sidebar.png"))
    out.replace("DARK_SCREENSHOT", base_url + AssetManifest.path("screenshots/android-dark-mode.png"))
  end

  static SERVICE_WORKER: String = """self.addEventListener("push", async (event) => {
  const data = await event.data.json()
  event.waitUntil(Promise.all([ showNotification(data), updateBadgeCount(data.options) ]))
})

async function showNotification({ title, options }) {
  return self.registration.showNotification(title, options)
}

async function updateBadgeCount({ data: { badge } }) {
  return self.navigator.setAppBadge?.(badge || 0)
}

self.addEventListener("notificationclick", (event) => {
  event.notification.close()

  const url = new URL(event.notification.data.path, self.location.origin).href
  event.waitUntil(openURL(url))
})

async function openURL(url) {
  const clients = await self.clients.matchAll({ type: "window" })
  const focused = clients.find((client) => client.focused)

  if (focused) {
    await focused.navigate(url)
  } else {
    await self.clients.openWindow(url)
  }
}
"""
end
