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
    unless dims[0].nil?
      # Ruby arithmetic: integers halve as integers; floats (scaled sizes, and the video
      # analyzer's widths) stay floats and print with a decimal point.
      float = dims[2] || dims[0].is_a?("float")
      half = float ? AttachmentPresentation.number(dims[0] / 2.0) : str(dims[0] / 2)
      data["frame_style"] = "width: " + half + "px; aspect-ratio: " + AttachmentPresentation.number(dims[0].to_f / dims[1]) + ";"
      data["width"] = float ? AttachmentPresentation.number(dims[0]) : str(dims[0])
      data["height"] = dims[2] || dims[1].is_a?("float") ? AttachmentPresentation.number(dims[1]) : str(dims[1])
    end
    data["thumb_path"] = Attachments.path(attachment["variant_blob_id"], attachment["filename"]) if variable
    data["poster_path"] = Attachments.path(attachment["preview_blob_id"], "preview.webp") unless attachment["preview_blob_id"].nil?
    data
  end

  # [width, height, scaled?]
  static def preview_dimensions(width, height)
    return [nil, nil, false] if width.nil? || height.nil?
    return [width, height, false] if width <= 1200 && height <= 800

    wf = 1200.0 / width
    hf = 800.0 / height
    scale = wf < hf ? wf : hf
    [width * scale, height * scale, true]
  end

  # Ruby's Float#to_s, near enough: integers keep a ".0".
  static def number(value)
    s = str(value)
    s.contains(".") ? s : s + ".0"
  end
end
