class SearchesController < ApplicationController
  # GET /searches
  def index
    query = @_query
    @query = query.blank? ? nil : query
    data = SearchPage.load(@_current_user_key, query, cookies["last_room"])
    html = data["html"]
    html = MessagePresenter.join(Message.find_many_ordered(data["keys"]), RoomPage.base_url(req)) if html.nil?
    @message_count = data["keys"].length
    @recent_searches = data["recent"]
    @return_to_room = data["return_to_room"]
    @q = params["q"]
    @page_title = "Search"
    @body_class = "sidebar searches"
    account = req["account"]
    sig = json_stringify([@q, @recent_searches.map { |s| s["query"] }, @return_to_room, @message_count,
                          account["updated_at"], @_current_user["updated_at"], @_current_user["role"]])
    @_render_cached_page("searches/index", "search:" + @_current_user_key, sig, {"messages": html, "csrf": csrf_token()})
  end

  # POST /searches
  def create
    query = @_query
    Search.record(@_current_user_key, query) unless query.blank?
    redirect("/searches?q=" + url_encode(query ?? ""))
  end

  # DELETE /searches/clear
  def clear
    Search.clear_for(@_current_user_key)
    redirect("/searches")
  end

  private

  # params[:q]&.gsub(/[^[:word:]]/, " ")
  def _query
    q = params["q"]
    q.nil? ? nil : Regex.replace_all("[^\\p{L}\\p{N}\\p{M}_]", q, " ")
  end
end
