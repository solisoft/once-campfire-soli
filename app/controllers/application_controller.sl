class ApplicationController < Controller
  static {
    this.layout = "application"
    this.before_action = fn(req) { Authentication.run(req) }
  }

  def _current_user
    req["current_user"]
  end

  def _current_user_key
    req["current_user"]["_key"]
  end

  def _account
    req["account"]
  end

  # Authorization#ensure_can_administer
  def _ensure_can_administer(record = nil)
    halt(403, "") unless User.can_administer?(@_current_user, record)
  end

  # RoomScoped#set_room: the membership (find_by! → 404) and its room.
  def _set_room_scoped(room_key)
    found = Membership.with_room_for(@_current_user_key, room_key)
    halt(404, "") if found.nil?

    @membership = found["membership"]
    @room = found["room"]
  end

  # TrackedRoomVisit
  def _remember_last_room_visited
    return nil if cookies["last_room"] == @room["_key"]

    set_cookie("last_room", @room["_key"], {"max_age": Authentication.TWENTY_YEARS})
  end

  def _last_room_visited
    last = cookies["last_room"]
    unless last.blank?
      found = Membership.with_room_for(@_current_user_key, last)
      return found["room"] unless found.nil?
    end
    Room.default_for_user(@_current_user_key)
  end

  def _flash(kind, message)
    session_set("flash_" + kind, message)
  end

  # The flash a page shows once, read by the layout.
  def _take_flash
    notice = session_get("flash_notice")
    alert = session_get("flash_alert")
    session_delete("flash_notice") unless notice.nil?
    session_delete("flash_alert") unless alert.nil?
    @flash_notice = notice
    @flash_alert = alert
  end

  def _render_page(view, status = 200)
    @_take_flash
    @layout = Layout.data(req)
    render(view, {}, {"status": status})
  end

  # A page whose surroundings only change with sig: rendered once per worker with markers
  # where the per-request values go (see PageCache), then reassembled from the parts.
  # values maps marker names to strings; the view outputs @marks[name] in their place.
  # content_sig identifies the values that are too big to hash (the messages): the ETag is
  # derived from it, sig and the small values, never from the first render's body.
  def _render_cached_page(view, name, sig, values, content_sig = "")
    @_take_flash
    return @_render_marked(view, values) unless @flash_notice.nil? && @flash_alert.nil?

    cached = PageCache.get(name)
    if cached.nil? || cached["sig"] != sig
      @marks = {}
      values.each do |k, v|
        @marks[k] = "%%CF:" + k + "%%"
      end
      @csrf = @marks["csrf"]
      @layout = Layout.data(req)
      response = render(view)
      cached = {"sig": sig, "parts": response["body"].split("%%CF:"), "headers": response["headers"], "status": response["status"]}
      PageCache.set(name, cached)
    end
    body = cached["parts"][0]
    small = []
    for part in cached["parts"].drop(1)
      segments = part.split("%%")
      value = values[segments[0]]
      small.push(value) if value.length < 200
      body += value + segments.drop(1).join("%%")
    end
    headers = {}
    cached["headers"].each do |k, v|
      headers[k] = v
    end
    headers["ETag"] = "W/\"" + Crypto.md5(name + "|" + sig + "|" + content_sig + "|" + small.join("|")) + "\""
    {"status": cached["status"], "headers": headers, "body": body}
  end

  def _render_marked(view, values)
    @marks = values
    @csrf = values["csrf"]
    @layout = Layout.data(req)
    render(view)
  end

  def _turbo_stream(body, status = 200)
    {"status": status, "headers": {"Content-Type": "text/vnd.turbo-stream.html; charset=utf-8"}, "body": body}
  end

  def _head(status, headers = {})
    {"status": status, "headers": headers, "body": ""}
  end

  def _turbo_stream_request?
    accept = req["headers"]["accept"] ?? ""
    accept.contains("text/vnd.turbo-stream.html")
  end
end
