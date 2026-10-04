class AccountsCustomStylesController < ApplicationController
  # GET /account/custom_styles/edit
  def edit
    @_ensure_can_administer
    @page_title = "Custom styles"
    @custom_styles = @_account["custom_styles"]
    @form_url = RoomPage.base_url(req) + "/account/custom_styles"
    @_render_page("accounts/custom_styles/edit")
  end

  # PATCH /account/custom_styles
  # PUT /account/custom_styles
  def update
    @_ensure_can_administer
    attrs = params["account"]
    styles = attrs.is_a?("hash") ? attrs["custom_styles"] : nil
    Account.update_fields({"custom_styles": styles})
    @_flash("notice", "✓")
    redirect("/account/custom_styles/edit")
  end
end
