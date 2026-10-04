# Messages::AttachmentPresentation: what messages/_attachment.html.slv draws.
class AttachmentPresentation
  static def data(attachment, message_data)
    ct = attachment["content_type"] ?? ""
    variable = Attachments.variable?(ct) && !attachment["variant_blob_id"].nil?
    video = Attachments.video?(ct)
    dims = AttachmentPresentation.preview_dimensions(attachment["width"], attachment["height"])
    data = {
      "kind": video ? "video" : (variable ? "image" : "file"),
      "filename": attachment["filename"],
      "blob_path": message_data["blob_path"], "download_path": message_data["download_path"],
      "width": dims[0], "height": dims[1]
    }
    if dims[0] != nil
      data["frame_style"] = "width: " + AttachmentPresentation.number(dims[0] / 2.0) + "px; aspect-ratio: " + AttachmentPresentation.number(dims[0].to_f / dims[1]) + ";"
    end
    data["thumb_path"] = Attachments.path(attachment["variant_blob_id"], attachment["filename"]) if variable
    data["poster_path"] = Attachments.path(attachment["preview_blob_id"], "preview.webp") unless attachment["preview_blob_id"].nil?
    data
  end

  static def preview_dimensions(width, height)
    return [nil, nil] if width.nil? || height.nil?
    return [width, height] if width <= 1200 && height <= 800

    wf = 1200.0 / width
    hf = 800.0 / height
    scale = wf < hf ? wf : hf
    [width * scale, height * scale]
  end

  # Ruby's Float#to_s, near enough: integers keep a ".0".
  static def number(value)
    s = str(value)
    s.contains(".") ? s : s + ".0"
  end
end
