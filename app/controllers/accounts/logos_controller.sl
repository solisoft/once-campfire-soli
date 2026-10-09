class AccountsLogosController < ApplicationController
  # GET /account/logo — the account logo (small or large variant), or the stock icon.
  def show
    account = req["account"]
    small = params["size"] == "small"
    etag = "W/\"logo-" + (account.nil? ? "0" : str(account["updated_at"])) + (small ? "-small" : "") + "\""
    return @_head(304, {"ETag": etag}) if req["headers"]["if-none-match"] == etag

    headers = {"Cache-Control": "max-age=300, public, stale-while-revalidate=604800", "ETag": etag,
               "Content-Type": "image/png", "Content-Disposition": "inline"}
    logo = account.nil? ? nil : account["logo"]
    variant = logo.nil? ? nil : logo[small ? "small_blob_id" : "large_blob_id"]
    return Attachments.response(variant, req, headers) unless variant.nil?

    file = small ? "app-icon-192.png" : "app-icon.png"
    {"status": 200, "headers": headers, "body": slurp("reference/app/assets/images/logos/" + file, "binary")}
  end

  # DELETE /account/logo
  def destroy
    @_ensure_can_administer
    account = req["account"]
    Attachments.delete_image_set(account["logo"]) unless account["logo"].nil?
    Account.update_fields({"logo": nil})
    redirect("/account/edit")
  end
end
