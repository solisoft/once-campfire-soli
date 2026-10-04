class UsersSidebarsController < ApplicationController
  # GET /users/me/sidebar
  def show
    data = Sidebar.load(@_current_user_key)
    me = @_current_user_key
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
    @can_create_rooms = User.administrator?(@_current_user) || !Account.restrict_room_creation?(req["account"])
    @rooms_stream = Cable.signed_stream_name("rooms")
    @user_rooms_stream = Cable.signed_stream_name("user:" + me + ":rooms")
    render("users/sidebars/show", {}, {"layout": false})
  end
end
