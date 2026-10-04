# Action Cable's protocol (actioncable-v1-json) on a Soli WebSocket route.
#
# A subscription joins the Soli channel "<stream>|<identifier>": the stream the Rails
# channel would stream_from, plus the identifier the client sent, which every message on it
# must echo. Broadcasting rebuilds the identifier the frontend's JSON.stringify produces
# for that stream's subscribers, so a broadcast is one channel fan-out.
#
# Presence subscriptions are remembered per connection in SoliKV, so a closed socket marks
# its rooms absent as PresenceChannel#unsubscribed would.
class Cable
  static GUARDED_SUFFIX: String = ":messages"

  # --- streams ----------------------------------------------------------------------------

  static def signed_stream_name(name)
    Signer.generate(name, "turbo_stream")
  end

  static def verified_stream_name(signed)
    Signer.verify(signed, "turbo_stream")
  end

  static def channel_name(stream, identifier)
    stream + "|" + identifier
  end

  # The identifier a <turbo-cable-stream-source> sends: { channel, signed_stream_name }.
  static def turbo_identifier(channel_class, stream)
    json_stringify({"channel": channel_class, "signed_stream_name": Cable.signed_stream_name(stream)})
  end

  # A Turbo Stream broadcast (Turbo::StreamsChannel or RoomMessagesChannel).
  static def broadcast_stream(stream, html)
    channel_class = stream.ends_with(Cable.GUARDED_SUFFIX) ? "RoomMessagesChannel" : "Turbo::StreamsChannel"
    identifier = Cable.turbo_identifier(channel_class, stream)
    Cable.send_to_channel(Cable.channel_name(stream, identifier), json_stringify({"identifier": identifier, "message": html}))
  end

  # ActionCable.server.broadcast on a stream a JS subscription listens to.
  static def broadcast_raw(stream, payload)
    identifier = Cable.identifier_for_stream(stream)
    return nil if identifier.nil?

    message = payload.is_a?("string") ? (JSON.parse(payload) rescue payload) : payload
    Cable.send_to_channel(Cable.channel_name(stream, identifier), json_stringify({"identifier": identifier, "message": message}))
  end

  static def identifier_for_stream(stream)
    return json_stringify({"channel": "UnreadRoomsChannel"}) if stream.ends_with("_unreads")
    return json_stringify({"channel": "ReadRoomsChannel"}) if stream.ends_with("_reads")

    m = Regex.capture("^typing_notifications:(?P<room>.+)$", stream)
    return nil if m.nil?

    "{\"channel\":\"TypingNotificationsChannel\",\"room_id\":" + m["room"] + "}"
  end

  static def send_to_channel(channel, payload)
    broadcast(channel, payload) rescue nil
  end

  # User#close_remote_connections: every socket of the user, told whether to reconnect.
  static def disconnect_user(user_key, reconnect)
    clients = ws_clients_in("cable_user:" + user_key) rescue []
    payload = json_stringify({"type": "disconnect", "reason": "remote", "reconnect": reconnect})
    for id in clients
      ws_send(id, payload) rescue nil
      ws_close(id, "remote") rescue nil
    end
  end

  # Action Cable's 3-second heartbeat, every connection at once.
  static def ping
    ws_broadcast(json_stringify({"type": "ping", "message": DateTime.now().to_unix()})) rescue nil
  end

  # --- the connection ---------------------------------------------------------------------

  static def handle(event)
    type = event["type"]
    return Cable.connect(event) if type == "connect"
    return Cable.disconnect(event) if type == "disconnect"
    return {} unless type == "message"

    data = JSON.parse(event["message"] ?? "") rescue nil
    return {} unless data.is_a?("hash")

    user = Authentication.user_from_cookie_header(event["headers"]["cookie"])
    return {"send": json_stringify({"type": "disconnect", "reason": "unauthorized", "reconnect": false}), "close": "unauthorized"} if user.nil?

    command = data["command"]
    identifier = data["identifier"] ?? ""
    params = JSON.parse(identifier) rescue nil
    return {} unless params.is_a?("hash")
    return Cable.subscribe(event, user, identifier, params) if command == "subscribe"
    return Cable.unsubscribe(event, user, identifier, params) if command == "unsubscribe"
    return Cable.perform(event, user, identifier, params, data["data"]) if command == "message"

    {}
  end

  static def connect(event)
    user = Authentication.user_from_cookie_header(event["headers"]["cookie"])
    if user.nil? || user["status"] != "active"
      return {"send": json_stringify({"type": "disconnect", "reason": "unauthorized", "reconnect": false}), "close": "unauthorized"}
    end

    {"send": json_stringify({"type": "welcome"}), "join": "cable_user:" + user["_key"]}
  end

  static def disconnect(event)
    key = "cable:presence:" + event["connection_id"]
    raw = Cache.get(key) rescue nil
    return {} if raw.blank?

    for membership_key in (JSON.parse(raw) rescue [])
      membership = Membership.find_hash(membership_key)
      Membership.disconnected(membership) unless membership.nil?
    end
    Cache.delete(key) rescue nil
    {}
  end

  static def confirm(identifier)
    json_stringify({"identifier": identifier, "type": "confirm_subscription"})
  end

  static def reject(identifier)
    {"send": json_stringify({"identifier": identifier, "type": "reject_subscription"})}
  end

  # The stream a subscription listens to, or nil when it is refused.
  static def stream_for(user, params)
    channel = params["channel"]
    if channel == "Turbo::StreamsChannel" || channel == "RoomMessagesChannel"
      stream = Cable.verified_stream_name(params["signed_stream_name"])
      return nil if stream.nil?

      # RoomStreamsAreAuthorized: room message streams only through RoomMessagesChannel,
      # and only for members.
      guarded = stream.ends_with(Cable.GUARDED_SUFFIX)
      return nil if guarded && channel != "RoomMessagesChannel"
      return nil if !guarded && channel == "RoomMessagesChannel"

      if guarded
        room_key = stream.replace("room:", "").replace(Cable.GUARDED_SUFFIX, "")
        return nil if Membership.find_for(user["_key"], room_key).nil?
      end
      return stream
    end
    return "user_" + user["_key"] + "_reads" if channel == "ReadRoomsChannel"
    return "user_" + user["_key"] + "_unreads" if channel == "UnreadRoomsChannel"
    return "heartbeat" if channel == "HeartbeatChannel"

    room_key = str(params["room_id"])
    if channel == "PresenceChannel" || channel == "TypingNotificationsChannel"
      return nil if Membership.find_for(user["_key"], room_key).nil?

      return channel == "PresenceChannel" ? "presence:" + room_key : "typing_notifications:" + room_key
    end
    nil
  end

  static def subscribe(event, user, identifier, params)
    stream = Cable.stream_for(user, params)
    return Cable.reject(identifier) if stream.nil?

    action = {"send": Cable.confirm(identifier), "join": Cable.channel_name(stream, identifier)}
    if params["channel"] == "PresenceChannel"
      membership = Membership.find_for(user["_key"], str(params["room_id"]))
      Membership.present(membership)
      Cable.remember_presence(event["connection_id"], membership["_key"], true)
      read = json_stringify({"identifier": json_stringify({"channel": "ReadRoomsChannel"}), "message": {"room_id": Cable.numeric(membership["room_id"])}})
      action["broadcast_channel"] = {"channel": Cable.channel_name("user_" + user["_key"] + "_reads", json_stringify({"channel": "ReadRoomsChannel"})), "message": read}
    end
    action
  end

  static def unsubscribe(event, user, identifier, params)
    stream = Cable.stream_for(user, params)
    return {} if stream.nil?

    if params["channel"] == "PresenceChannel"
      membership = Membership.find_for(user["_key"], str(params["room_id"]))
      unless membership.nil?
        Membership.disconnected(membership)
        Cable.remember_presence(event["connection_id"], membership["_key"], false)
      end
    end
    {"leave": Cable.channel_name(stream, identifier)}
  end

  # Channel actions: PresenceChannel#present/absent/refresh, TypingNotificationsChannel#start/stop.
  static def perform(event, user, identifier, params, data)
    payload = JSON.parse(data ?? "{}") rescue {}
    action = payload["action"]
    channel = params["channel"]
    room_key = str(params["room_id"])
    if channel == "PresenceChannel"
      membership = Membership.find_for(user["_key"], room_key)
      return {} if membership.nil?

      Membership.present(membership) if action == "present"
      Membership.disconnected(membership) if action == "absent"
      Membership.refresh_connection(membership) if action == "refresh"
      return {}
    end
    if channel == "TypingNotificationsChannel" && (action == "start" || action == "stop")
      return {} if Membership.find_for(user["_key"], room_key).nil?

      message = {"action": action, "user": {"id": Cable.numeric(user["_key"]), "name": user["name"]}}
      return {"broadcast_channel": {"channel": Cable.channel_name("typing_notifications:" + room_key, identifier),
                                    "message": json_stringify({"identifier": identifier, "message": message})}}
    end
    {}
  end

  static def remember_presence(connection_id, membership_key, present)
    key = "cable:presence:" + connection_id
    raw = Cache.get(key) rescue nil
    keys = raw.blank? ? [] : (JSON.parse(raw) rescue [])
    keys = present ? (keys + [membership_key]).uniq : keys.filter { |k| k != membership_key }
    Cache.set(key, json_stringify(keys), 86400) rescue nil
  end

  # Rails ids are integers in JSON; ours are integer-valued keys.
  static def numeric(key)
    Regex.matches("^[0-9]{1,15}$", key) ? int(key) : key
  end
end
