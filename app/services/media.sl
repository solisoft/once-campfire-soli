# Video previews (Active Storage's ffmpeg previewer): a WebP poster of the first frame,
# with the video's dimensions from ffprobe.
class Media
  static def video_preview(file, attachment)
    dir = "tmp/media"
    System.run_sync(["mkdir", "-p", dir]) rescue nil
    base = dir + "/" + UUID.v4()
    input = base + ".video"
    output = base + ".webp"
    barf(input, Base64.decode(file["data"])) rescue nil
    probe = System.run_sync(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0", input]) rescue nil
    unless probe.nil?
      dims = str(probe["stdout"] ?? "").trim.split(",")
      # Active Storage's video analyzer reports floats; dimensions already known are kept.
      if dims.length == 2 && attachment["width"].nil?
        attachment["width"] = dims[0].to_f rescue nil
        attachment["height"] = dims[1].to_f rescue nil
      end
    end
    System.run_sync(["ffmpeg", "-y", "-v", "error", "-i", input, "-vframes", "1", "-vf", "scale='min(1200,iw)':'min(800,ih)':force_original_aspect_ratio=decrease", output]) rescue nil
    poster = slurp(output, "binary") rescue nil
    unless poster.nil?
      attachment["preview_blob_id"] = Attachments.store(Base64.encode(poster), "preview.webp", "image/webp")
    end
    System.run_sync(["rm", "-f", input, output]) rescue nil
  end
end
