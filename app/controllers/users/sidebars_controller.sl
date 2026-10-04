class UsersSidebarsController < ApplicationController
  # GET /users/me/sidebar
  def show
    me = @_current_user_key
    name = "sidebar:" + me
    can_create = User.administrator?(@_current_user) || !Account.restrict_room_creation?(req["account"])
    context = json_stringify([@_current_user["updated_at"], can_create])
    cached = PageCache.get(name)
    known = cached.nil? || cached["context"] != context ? "" : cached["sig"]
    data = Sidebar.load(me, known)
    return {"status": 200, "headers": cached["headers"], "body": cached["body"]} if data["same"]

    directs = []
    others = []
    for m in data["memberships"]
      if m["room"]["type"] == "Rooms::Direct"
        m["others"] = Present.users(m["members"].filter { |u| u["_key"] != me })
        m["others"] = Present.users(m["members"].filter { |u| u["_key"] == me }) if m["others"].length == 0
        directs.push(m)
      else
        others.push(m)
      end
    end
    @direct_memberships = directs.sort_by { |m| m["room"]["updated_at"] }.reverse
    @other_memberships = others
    @direct_placeholder_users = Present.users(data["placeholders"])
    @current_user = Present.user(@_current_user)
    @can_create_rooms = can_create
    @rooms_stream = Cable.signed_stream_name("rooms")
    @user_rooms_stream = Cable.signed_stream_name("user:" + me + ":rooms")
    response = render("users/sidebars/show", {}, {"layout": false})
    PageCache.set(name, {"sig": data["sig"], "context": context, "headers": response["headers"], "body": response["body"]})
    response
  end
end
