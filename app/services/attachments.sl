# Active Storage on SoliDB blobs: every original and every variant is a blob in the
# "attachments" blob collection, served streamed (with Range) by AttachmentsController.
class Attachments
  static COLLECTION: String = "attachments"
  static THUMB_MAX_WIDTH: Int = 1200
  static THUMB_MAX_HEIGHT: Int = 800
  # Active Storage's variable content types, less the ones config/initializers/vips.rb drops.
  static VARIABLE_TYPES: Array = ["image/png", "image/gif", "image/jpeg", "image/pjpeg", "image/tiff", "image/webp", "image/avif", "image/heic", "image/heif"]

  static def db
    handle = Solidb(getenv("SOLIDB_HOST") ?? "http://localhost:6745", getenv("SOLIDB_DATABASE") ?? "once_campfire_soli")
    handle.auth(getenv("SOLIDB_USERNAME") ?? "admin", getenv("SOLIDB_PASSWORD") ?? "admin")
    handle
  end

  static def store(data_base64, filename, content_type)
    Attachments.db.store_blob(Attachments.COLLECTION, data_base64, filename, content_type)
  end

  static def delete_blob(blob_id)
    Attachments.db.delete_blob(Attachments.COLLECTION, blob_id) rescue nil unless blob_id.nil?
  end

  # Every blob an attachment hash points at.
  static def delete_for(attachment)
    return nil if attachment.nil?

    for key in ["blob_id", "variant_blob_id", "preview_blob_id"]
      Attachments.delete_blob(attachment[key])
    end
  end

  static def variable?(content_type)
    Attachments.VARIABLE_TYPES.include?((content_type ?? "").downcase)
  end

  static def video?(content_type)
    (content_type ?? "").starts_with("video/")
  end

  # A message attachment: the original, analyzed (width/height), with its :thumb variant
  # (resize_to_limit 1200×800) or, for a video, a WebP poster frame.
  static def create_message_attachment(file)
    return nil if file.nil?

    content_type = file["content_type"].blank? ? "application/octet-stream" : file["content_type"]
    attachment = {
      "blob_id": Attachments.store(file["data"], file["filename"], content_type),
      "filename": file["filename"], "content_type": content_type, "byte_size": file["size"],
      "width": nil, "height": nil, "variant_blob_id": nil, "preview_blob_id": nil
    }

    if Attachments.variable?(content_type)
      image = Image.from_buffer(file["data"]) rescue nil
      unless image.nil?
        attachment["width"] = image.width
        attachment["height"] = image.height
        thumb = Attachments.resize_to_limit(image, Attachments.THUMB_MAX_WIDTH, Attachments.THUMB_MAX_HEIGHT)
        attachment["variant_blob_id"] = Attachments.store(thumb.to_buffer(), file["filename"], content_type)
      end
    elsif Attachments.video?(content_type)
      Media.video_preview(file, attachment)
    end
    attachment
  end

  # image_processing's resize_to_limit: shrink to fit, never enlarge.
  static def resize_to_limit(image, max_width, max_height)
    w = image.width
    h = image.height
    return image if w <= max_width && h <= max_height

    scale_w = max_width.to_f / w
    scale_h = max_height.to_f / h
    scale = scale_w < scale_h ? scale_w : scale_h
    image.resize((w * scale).round(), (h * scale).round())
  end

  # An avatar (User::Avatar, variant :square → 512×512 limit, WebP) or a logo
  # (Account, variants :large 512 and :small 192, PNG).
  static def create_image_set(file, variants)
    return nil if file.nil? || file["size"] == 0

    record = {"blob_id": Attachments.store(file["data"], file["filename"], file["content_type"]),
              "filename": file["filename"], "content_type": file["content_type"]}
    image = Attachments.variable?(file["content_type"]) ? (Image.from_buffer(file["data"]) rescue nil) : nil
    unless image.nil?
      variants.each do |name, spec|
        variant = Attachments.resize_to_limit(image, spec["size"], spec["size"]).format(spec["format"])
        record[name + "_blob_id"] = Attachments.store(variant.to_buffer(), name + "." + spec["format"], "image/" + spec["format"])
      end
    end
    record
  end

  static def delete_image_set(record)
    return nil if record.nil?

    record.each do |k, v|
      Attachments.delete_blob(v) if k.ends_with("blob_id")
    end
  end

  # rails_blob_path: a signed, unguessable URL for a blob.
  static def path(blob_id, filename, disposition = nil)
    token = Signer.generate(blob_id, "blob")
    path = "/attachments/" + token + "/" + url_encode(filename ?? "file")
    disposition.nil? ? path : path + "?disposition=" + disposition
  end

  static def blob_from_token(token)
    Signer.verify(token, "blob")
  end
end
