# turbo_stream.* tag builders.
class TurboStream
  static def action(action, target, html = nil, attributes = {})
    extra = ""
    attributes.each do |k, v|
      extra += " " + k + "=\"" + html_escape(str(v)) + "\""
    end
    return "<turbo-stream action=\"" + action + "\" target=\"" + target + "\"" + extra + "></turbo-stream>" if html.nil?

    "<turbo-stream action=\"" + action + "\" target=\"" + target + "\"" + extra + "><template>" + html + "</template></turbo-stream>"
  end

  static def append(target, html, attributes = {})
    TurboStream.action("append", target, html, attributes)
  end

  static def prepend(target, html, attributes = {})
    TurboStream.action("prepend", target, html, attributes)
  end

  static def replace(target, html, attributes = {})
    TurboStream.action("replace", target, html, attributes)
  end

  static def remove(target)
    TurboStream.action("remove", target)
  end
end
