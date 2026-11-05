module DiscourseGraphQL
  module NativeRequest
    def self.included(controller)
      controller.skip_before_action :clear_notifications
      controller.skip_after_action :perform_refresh_session
    end

    def initialize(request:)
      super()
      set_request!(ActionDispatch::Request.new(request.env.dup))
      set_response!(ActionDispatch::Response.new)
      self.request.format = :json
    end
  end
end
