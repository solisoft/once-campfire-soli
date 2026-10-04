class SearchesController < ApplicationController
  # GET /searches
  def index
    query = @_query
    @query = query.blank? ? nil : query
    data = SearchPage.load(@_current_user_key, query, cookies["last_room"])
    @messages_html = MessagePresenter.join(data["messages"], RoomPage.base_url(req))
    @message_count = data["messages"].length
    @recent_searches = data["recent"]
    @return_to_room = data["return_to_room"]
    @q = params["q"]
    @page_title = "Search"
    @body_class = "sidebar searches"
    @_render_page("searches/index")
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
