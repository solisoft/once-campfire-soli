class AttachmentsController < ApplicationController
  # GET /attachments/:token/:filename — a blob by its signed id (rails_blob_path).
  def show
    blob_id = Attachments.blob_from_token(req["params"]["token"])
    return @_head(404) if blob_id.nil?

    meta = Db.find_row("blobs", blob_id)
    return @_head(404) if meta.nil?

    disposition = params["disposition"] == "attachment" ? "attachment" : "inline"
    filename = meta["filename"] ?? "file"
    Attachments.response(blob_id, req, {
      "Content-Type": meta["content_type"] ?? "application/octet-stream",
      "Content-Disposition": disposition + "; filename=\"" + filename.replace("\"", "") + "\"",
      "Cache-Control": "max-age=3600, public", "X-Content-Type-Options": "nosniff"
    })
  end
end
