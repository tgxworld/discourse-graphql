module DiscourseGraphQL
  module NativeRequest
    extend ActiveSupport::Concern

    included do
      skip_before_action :clear_notifications
      skip_after_action :perform_refresh_session
    end

    class_methods do
      def requires_login_arg
        superclass.requires_login_arg
      end

      def allowed_when_archived?(action)
        superclass.allowed_when_archived?(action)
      end
    end

    def initialize(request:, request_method: nil)
      super()
      environment = request.env.dup
      environment.delete("rack.hijack")
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
