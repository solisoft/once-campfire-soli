# Users::SidebarHelper#sidebar_turbo_frame_tag
def sidebar_turbo_frame_tag(src, inner_html)
  attrs = {"target": "_top", "data": {
    "turbo_permanent": true, "controller": "rooms-list read-rooms turbo-frame", "rooms_list_unread_class": "unread",
    "action": "presence:present@window->rooms-list#read read-rooms:read->rooms-list#read turbo:frame-load->rooms-list#loaded refresh-room:visible@window->turbo-frame#reload"
  }}
  attrs["src"] = src unless src.blank?
  turbo_frame_tag("user_sidebar", attrs, inner_html)
end

# members.map { initials of up to three words }.to_sentence(two_words_connector: "+")
def direct_initials(members)
  names = members.map { |m| m["name"].split(" ").take(3).map { |w| w.chars()[0].upcase }.join("") }
  return names[0] + "+" + names[1] if names.length == 2

  names.take(names.length - 1).join(", ") + ", and " + names.last
end
