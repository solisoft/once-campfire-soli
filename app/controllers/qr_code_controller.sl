class QrCodeController < ApplicationController
  # GET /qr_code/:id — the URL base64-encoded in :id, as an SVG QR code cached for a year.
  def show
    url = Base64.urlsafe_decode(req["params"]["id"]) rescue nil
    halt(404, "") if url.nil? || !url.is_a?("string")

    headers = {"Content-Type": "image/svg+xml; charset=utf-8", "Cache-Control": "max-age=31556952, public"}
    {"status": 200, "headers": headers, "body": QrCode.svg(url)}
  end
end
