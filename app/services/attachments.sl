# Active Storage's disk service: every original and every variant is a file under the blobs
# directory next to the database file (storage/blobs; key[0..2]/key[2..4]/key, Active
# Storage's layout), described by a row of the blobs table, and served (with Range) by
# AttachmentsController.
class Attachments
  static THUMB_MAX_WIDTH: Int = 1200
  static THUMB_MAX_HEIGHT: Int = 800
  # Active Storage's variable content types, less the ones config/initializers/vips.rb drops.
  static VARIABLE_TYPES: Array = ["image/png", "image/gif", "image/jpeg", "image/pjpeg", "image/tiff", "image/webp", "image/avif", "image/heic", "image/heif"]

  # "storage/blobs" for DATABASE_URL=sqlite://storage/campfire.sqlite3
  static def root
    path = (getenv("DATABASE_URL") ?? "sqlite://storage/campfire.sqlite3").replace("sqlite://", "").split("?")[0]
    parts = path.split("/")
    parts.length > 1 ? parts.take(parts.length - 1).join("/") + "/blobs" : "blobs"
  end

  static def file_path(blob_id)
    Attachments.root + "/" + blob_id.substring(0, 2) + "/" + blob_id.substring(2, 4) + "/" + blob_id
  end

  # The blob's key: 28 lowercase letters and digits, like Active Storage's.
  static def generate_key
    chars = "abcdefghijklmnopqrstuvwxyz0123456789"
    key = ""
    for b in Crypto.random_bytes(28)
      key += chars[b % 36]
    end
    key
  end

  static def store(data_base64, filename, content_type)
    data = Base64.decode(data_base64)
    key = Attachments.generate_key
    path = Attachments.file_path(key)
    mkdir_p(path.substring(0, path.length - key.length - 1))
    barf(path, data)
    Db.insert("blobs", {"_key": key, "filename": filename ?? "file", "content_type": content_type,
                        "byte_size": data.length, "created_at": Clock.now})
    key
  end

  # The blob's bytes, as slurp(path, "binary") reads them; nil when the file is gone.
  static def read(blob_id)
    slurp(Attachments.file_path(blob_id), "binary") rescue nil
  end

  static def delete_blob(blob_id)
    return nil if blob_id.nil?

    Db.delete_row("blobs", blob_id)
    File.delete(Attachments.file_path(blob_id)) rescue nil
  end

  # Every blob an attachment hash points at.
  static def delete_for(attachment)
    return nil if attachment.nil?

    for key in ["blob_id", "variant_blob_id", "preview_blob_id"]
      Attachments.delete_blob(attachment[key])
    end
  end

  # The blob as a response: whole, or the one byte range asked for (video seeking), with the
  # caller's headers.
  static def response(blob_id, req, headers)
    meta = Db.find_row("blobs", blob_id)
    return {"status": 404, "headers": {}, "body": ""} if meta.nil?

    data = Attachments.read(blob_id)
    return {"status": 404, "headers": {}, "body": ""} if data.nil?

    size = data.length
    headers["Accept-Ranges"] = "bytes"
    wanted = Regex.capture("^bytes=(?P<first>\\d*)-(?P<last>\\d*)$", req["headers"]["range"] ?? "")
    return {"status": 200, "headers": headers, "body": data} if wanted.nil? || (wanted["first"] == "" && wanted["last"] == "")

    first_byte = 0
    last_byte = size - 1
    if wanted["first"] == ""
      first_byte = size - int(wanted["last"])
      first_byte = 0 if first_byte < 0
    else
      first_byte = int(wanted["first"])
      last_byte = int(wanted["last"]) unless wanted["last"] == ""
    end
    last_byte = size - 1 if last_byte > size - 1
    if first_byte > last_byte || first_byte >= size
      headers["Content-Range"] = "bytes */" + str(size)
      return {"status": 416, "headers": headers, "body": ""}
    end

    headers["Content-Range"] = "bytes " + str(first_byte) + "-" + str(last_byte) + "/" + str(size)
    {"status": 206, "headers": headers, "body": data.slice(first_byte, last_byte + 1)}
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
