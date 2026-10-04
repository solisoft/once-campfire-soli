# After bin/import-seed: the fields the app derives from a message (plain text, search text),
# image variants, and no stale presentation HTML.
for m in Message.all
  doc = m.to_h()
  attachment = doc["attachment"]
  plain = attachment.nil? ? RichText.plain_text(doc["body"]) : (attachment["filename"] ?? "")
  fields = {"plain_text": plain, "search_text": Stemmer.index_text(plain), "html": nil, "html_key": nil}
  if !attachment.nil? && attachment["variant_blob_id"].nil? && Attachments.variable?(attachment["content_type"])
    data = Attachments.db.get_blob(Attachments.COLLECTION, attachment["blob_id"])
    image = Image.from_buffer(data) rescue nil
    unless image.nil?
      thumb = Attachments.resize_to_limit(image, Attachments.THUMB_MAX_WIDTH, Attachments.THUMB_MAX_HEIGHT)
      attachment["variant_blob_id"] = Attachments.store(thumb.to_buffer(), attachment["filename"], attachment["content_type"])
      fields["attachment"] = attachment
    end
  end
  Message.update(m._key, fields)
end

for u in User.all
  avatar = u.avatar
  next if avatar.nil? || !avatar["square_blob_id"].nil?

  data = Attachments.db.get_blob(Attachments.COLLECTION, avatar["blob_id"])
  image = Image.from_buffer(data) rescue nil
  next if image.nil?

  square = Attachments.resize_to_limit(image, 512, 512).format("webp")
  avatar["square_blob_id"] = Attachments.store(square.to_buffer(), "square.webp", "image/webp")
  User.update(u._key, {"avatar": avatar})
end

print("derived fields done")
