# RoomsHelper, Rooms::InvolvementsHelper and Users::FilterHelper, for the room settings
# pages. Rooms come in as hashes; whether the viewer may administer one is computed by the
# controller.

# RoomsHelper#button_to_delete_room
def button_to_delete_room(room, url, display_name)
  button_to(url, {"method": "delete", "class": "btn btn--negative max-width", "aria": {"label": "Delete " + (room["name"] ?? "")},
                  "data": {"turbo_confirm": "Are you sure you want to delete this room and all messages in it? This can’t be undone."}},
            image_tag("trash.svg", {"aria": {"hidden": "true"}, "size": 20}) + "<span class=\"overflow-ellipsis\">" + html_escape(display_name ?? "") + "</span>")
end

# RoomsHelper#submit_room_button_tag
def submit_room_button_tag
  "<button name=\"button\" type=\"submit\" class=\"btn btn--reversed txt-large center\">" +
    image_tag("check.svg", {"aria": {"hidden": "true"}, "size": 20}) + "<span class=\"for-screen-reader\">Save</span></button>"
end

# Users::FilterHelper#user_filter_search_tag
def user_filter_search_tag
  "<input type=\"search\" id=\"search\" autocorrect=\"off\" autocomplete=\"off\" data-1p-ignore=\"true\" class=\"input input--transparent full-width\" placeholder=\"Filter…\" data-action=\"input-&gt;filter#filter\">"
end

def room_dom_id(room, prefix)
  prefix + "_" + room["type"].downcase.replace("::", "_") + "_" + room["_key"]
end

# Rooms::InvolvementsHelper#button_to_change_involvement
def button_to_change_involvement(room, involvement)
  label_id = room_dom_id(room, "involvement_label")
  button_to("/rooms/" + room["_key"] + "/involvement", {
    "method": "put", "params": {"involvement": next_involvement_for(room, involvement)},
    "role": "checkbox", "aria": {"checked": "true", "labelledby": label_id}, "tabindex": 0, "class": "btn " + involvement
  }, image_tag("notification-bell-" + involvement + ".svg", {"aria": {"hidden": "true"}, "size": 20}) +
     "<span class=\"for-screen-reader\" id=\"" + label_id + "\">" + humanize_involvement(involvement) + "</span>")
end

def humanize_involvement(involvement)
  return "Notifying about @ mentions" if involvement == "mentions"
  return "Notifying about all messages" if involvement == "everything"
  return "Notifications are off" if involvement == "nothing"

  "Notifications are off and room invisible in sidebar"
end

def next_involvement_for(room, involvement)
  order = room["type"] == "Rooms::Direct" ? ["everything", "nothing"] : ["mentions", "everything", "nothing", "invisible"]
  i = 0
  while i < order.length
    return (i + 1 < order.length ? order[i + 1] : order[0]) if order[i] == involvement

    i += 1
  end
  order[0]
end
