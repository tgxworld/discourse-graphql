module DiscourseGraphQL
  module NativeRequest
    def self.included(controller)
      controller.skip_before_action :clear_notifications
      controller.skip_after_action :perform_refresh_session
    end

    def initialize(request:, request_method: nil)
      super()
      environment = request.env.dup
      if request_method
        environment["REQUEST_METHOD"] = request_method
        environment.delete("rack.methodoverride.original_method")
      end
      set_request!(ActionDispatch::Request.new(environment))
      set_response!(ActionDispatch::Response.new)
      self.request.format = :json
    end
  end
end
