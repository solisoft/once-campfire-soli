class UnfurlLinksController < ApplicationController
  # POST /unfurl_link — a pasted link's Open Graph metadata as JSON, or 204 without any.
  def create
    url = params["url"]
    halt(400, "") if url.blank?

    metadata = OpengraphMetadata.from_url(url.to_s)
    return @_head(204) if metadata.nil?

    # render json: opengraph serializes the model's instance variables, validation state included.
    metadata["context_for_validation"] = {"context": nil}
    metadata["errors"] = {}
    {"status": 200, "headers": {"Content-Type": "application/json; charset=utf-8"}, "body": json_stringify(metadata)}
  end
end
