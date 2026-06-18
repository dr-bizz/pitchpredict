module Admin
  class BaseController < ApplicationController
    before_action :require_admin

    private

    def require_admin
      return if Current.user&.admin?

      redirect_to root_path, alert: "You don't have access to the admin area."
    end
  end
end
