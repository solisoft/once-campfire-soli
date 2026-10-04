# users/profiles/_transfer: the user's sign-in link (session_transfer_url(user.transfer_id)) and
# the QR code path QrCodeHelper#link_to_zoom_qr_code points at.
class SessionTransfers
  static def link(req, user, current_user)
    url = RoomPage.base_url(req) + "/session/transfers/" + User.transfer_id(user)
    {"url": url, "qr_path": SessionTransfers.qr_code_path(url), "self": user["_key"] == current_user["_key"]}
  end

  # Base64.urlsafe_encode64 keeps the padding; Soli's urlsafe_encode drops it.
  static def qr_code_path(url)
    id = Base64.urlsafe_encode(url)
    padding = (4 - id.length % 4) % 4
    "/qr_code/" + id + "=" * padding
  end

  # ApplicationHelper#link_back: the referrer, unless it is missing or this very page.
  static def back_url(req)
    referrer = req["headers"]["referer"]
    return "/" if referrer.blank?

    here = RoomPage.base_url(req) + req["path"] + Authentication.query_suffix(req)
    referrer == here ? "/" : referrer
  end
end
