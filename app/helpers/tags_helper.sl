# ActionView's tag builders, reduced to what the ported views use. Attribute hashes nest
# "data" and "aria" like Rails: {"data": {"turbo_frame": "_top"}} → data-turbo-frame="_top".

def tag_attributes(attrs)
  return "" if attrs.nil?

  out = ""
  attrs.each do |name, value|
    if (name == "data" || name == "aria") && value.is_a?("hash")
      value.each do |k, v|
        out += tag_attribute(name + "-" + k.replace("_", "-"), v)
      end
    else
      out += tag_attribute(name, value)
    end
  end
  out
end

def tag_attribute(name, value)
  return "" if value.nil? || value == false
  return " " + name + "=\"" + name + "\"" if value == true && tag_boolean_attribute?(name)

  " " + name + "=\"" + html_escape(str(value)) + "\""
end

def tag_boolean_attribute?(name)
  ["hidden", "disabled", "checked", "selected", "readonly", "required", "autofocus", "multiple", "controls", "contents"].include?(name)
end

def content_tag(name, content, attrs = {})
  "<" + name + tag_attributes(attrs) + ">" + (content ?? "") + "</" + name + ">"
end

# image_tag(source, {"size": 20, "aria": {"hidden": "true"}, …}): the given options, then src,
# then the width and height a size expands to, in Rails' order.
def image_tag(source, attrs = {})
  src = source.starts_with("/") || source.starts_with("http") ? source : asset_path(source)
  options = {}
  size = nil
  attrs.each do |k, v|
    if k == "size"
      size = str(v).split("x")
    else
      options[k] = v
    end
  end
  options["src"] = src
  unless size.nil?
    options["width"] = size[0]
    options["height"] = size.length > 1 ? size[1] : size[0]
  end
  "<img" + tag_attributes(options) + " />"
end

def hidden_aria
  {"hidden": "true"}
end

# Users::AvatarsHelper#avatar_tag, for a user decorated by Present.user.
def avatar_tag(user, attrs = {})
  img_attrs = {"aria": {"hidden": "true"}, "size": 48}
  attrs.each do |k, v|
    img_attrs[k] = v
  end
  "<a title=\"" + html_escape(user["title"] ?? user["name"]) + "\" class=\"btn avatar\" data-turbo-frame=\"_top\" href=\"/users/" +
    user["_key"] + "\">" + image_tag(user["avatar_path"], img_attrs) + "</a>"
end

# TimeHelper#local_datetime_tag
def local_datetime_tag(ms, style = "time", attrs = {})
  options = {}
  attrs.each do |k, v|
    options[k] = v
  end
  options["datetime"] = iso8601_ms(ms)
  options["data"] = {"local_time_target": style}
  content_tag("time", "", options)
end

def iso8601_ms(ms)
  DateTime.from_unix(ms / 1000).utc().to_iso().replace("+00:00", "Z")
end

def csrf_hidden_field
  "<input type=\"hidden\" name=\"_csrf_token\" value=\"" + csrf_token() + "\" autocomplete=\"off\" />"
end

def method_hidden_field(method)
  "<input type=\"hidden\" name=\"_method\" value=\"" + method + "\" autocomplete=\"off\" />"
end

# button_to(url, {"method": "delete", "class": …, "form_class": …, "data": …}, inner_html)
# No token field: Turbo sends X-CSRF-Token from the csrf-token meta tag, and buttons inside
# shared cached fragments must not carry one session's token.
def button_to(url, options, inner_html)
  method = options["method"] ?? "post"
  action = url
  unless options["params"].nil?
    query = []
    options["params"].each do |name, value|
      for v in (value.is_a?("array") ? value : [value])
        query.push(url_encode(name) + "=" + url_encode(str(v)))
      end
    end
    action = url + "?" + query.join("&")
  end
  form_attrs = {"class": options["form_class"] ?? "button_to", "method": "post", "action": action}
  form_attrs["data"] = options["form_data"] unless options["form_data"].nil?
  button_attrs = {}
  options.each do |k, v|
    button_attrs[k] = v unless ["method", "form_class", "form_data", "params"].include?(k)
  end
  button_attrs["type"] = "submit"
  hidden = method == "post" ? "" : method_hidden_field(method)
  "<form" + tag_attributes(form_attrs) + ">" + hidden + "<button" + tag_attributes(button_attrs) + ">" + inner_html + "</button></form>"
end

def link_back_to(destination)
  "<a class=\"btn\" href=\"" + html_escape(destination) + "\">" + image_tag("arrow-left.svg", {"aria": {"hidden": "true"}, "size": 20}) +
    "<span class=\"for-screen-reader\">Go Back</span></a>"
end

def dom_id(prefix, key, suffix = nil)
  suffix.nil? ? prefix + "_" + key : suffix + "_" + prefix + "_" + key
end

def turbo_frame_tag(id, attrs, inner_html)
  options = {"id": id}
  attrs.each do |k, v|
    options[k] = v
  end
  "<turbo-frame" + tag_attributes(options) + ">" + inner_html + "</turbo-frame>"
end

def turbo_stream_from(signed_stream_name, channel = "Turbo::StreamsChannel")
  "<turbo-cable-stream-source channel=\"" + channel + "\" signed-stream-name=\"" + html_escape(signed_stream_name) + "\"></turbo-cable-stream-source>"
end
