class AccountsJoinCodesController < ApplicationController
  # POST /account/join_code — Account#reset_join_code
  def create
    @_ensure_can_administer
    Account.update_fields({"join_code": Account.generate_join_code})
    redirect("/account/edit")
  end
end
