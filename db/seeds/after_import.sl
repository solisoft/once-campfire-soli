# After bin/import-seed: the fields the app derives from a message (its plain text, which the
# search index takes), image variants, and no stale presentation HTML.
for m in Db.rows("SELECT " + Db.json("messages", "m") + " AS j FROM messages m ORDER BY m._key")
  attachment = m["attachment"]
  plain = attachment.nil? ? RichText.plain_text(m["body"]) : (attachment["filename"] ?? "")
  fields = {"plain_text": plain, "html": nil, "html_key": nil}
  if !attachment.nil? && attachment["preview_blob_id"].nil? && Attachments.video?(attachment["content_type"])
    data = Base64.encode(Attachments.read(attachment["blob_id"]))
    Media.video_preview({"data": data, "filename": attachment["filename"]}, attachment)
    fields["attachment"] = attachment
  end
  if !attachment.nil? && attachment["variant_blob_id"].nil? && Attachments.variable?(attachment["content_type"])
    image = Image.from_buffer(Base64.encode(Attachments.read(attachment["blob_id"]))) rescue nil
    unless image.nil?
      thumb = Attachments.resize_to_limit(image, Attachments.THUMB_MAX_WIDTH, Attachments.THUMB_MAX_HEIGHT)
      attachment["variant_blob_id"] = Attachments.store(thumb.to_buffer(), attachment["filename"], attachment["content_type"])
      fields["attachment"] = attachment
    end
  end
  Db.update_row("messages", m["_key"], fields)
end

for u in Db.rows("SELECT " + Db.json("users", "u") + " AS j FROM users u WHERE u.avatar IS NOT NULL")
  avatar = u["avatar"]
  next unless avatar["square_blob_id"].nil?

  image = Image.from_buffer(Base64.encode(Attachments.read(avatar["blob_id"]))) rescue nil
  next if image.nil?

  square = Attachments.resize_to_limit(image, 512, 512).format("webp")
  avatar["square_blob_id"] = Attachments.store(square.to_buffer(), "square.webp", "image/webp")
  Db.update_row("users", u["_key"], {"avatar": avatar})
end

print("derived fields done")
