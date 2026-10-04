# RichTextHelper#mention_prompt_tag
def mention_prompt_tag(room_key)
  "<lexxy-prompt trigger=\"@\" name=\"mention\" src=\"/autocompletable/users?room_id=" + room_key + "\" remote-filtering=\"true\" empty-results=\"No matches\"></lexxy-prompt>"
end
