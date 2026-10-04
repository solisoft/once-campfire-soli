def recent_searches_html(recent)
  html = ""
  for search in recent
    html += "<a class=\"align-center gap room btn txt-nowrap\" href=\"/searches?q=" + url_encode(search["query"]) + "\">\n        <span class=\"overflow-ellipsis\">“" +
      html_escape(search["query"]) + "”</span>\n</a>"
  end
  if recent.length > 0
    html += button_to("/searches/clear", {"method": "delete", "class": "btn searches__btn", "data": {"turbo_confirm": "Are you sure you want to clear your recent searches?"}},
      image_tag("broom.svg", {"aria": {"hidden": "true"}}) + "<span class=\"for-screen-reader\">Clear recent searches</span>")
  end
  html
end
