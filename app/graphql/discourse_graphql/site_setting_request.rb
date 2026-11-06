module DiscourseGraphQL
  class SiteSettingRequest < ::Admin::SiteSettingsController
    include NativeRequest

    prepend_before_action :ensure_native_admin_constraints

    def initialize(request:, request_method:)
      @source_request = request
      super
    end

    private

    def prepare_native_action(parameters:, action:, path:, route_parameters: {})
      token_key = self.class.request_forgery_protection_token
      token = @source_request.parameters[token_key]
      parameters = parameters.merge(token_key => token) if token
      environment = request.env.dup
      environment.delete_if do |key, _value|
        key.start_with?("action_dispatch.request.", "rack.request.")
      end
      environment.delete("RAW_POST_DATA")
      environment.delete("rack.methodoverride.original_method")
      environment.delete(Auth::DefaultCurrentUserProvider::CURRENT_USER_KEY)
      environment["SCRIPT_NAME"] = Discourse.base_path
      environment["PATH_INFO"] = path
      environment["action_dispatch.original_path_info"] = path
      environment["QUERY_STRING"] = request.get? ? Rack::Utils.build_nested_query(parameters) : ""
      body = request.get? ? "" : JSON.generate(parameters)
      environment["rack.input"] = StringIO.new(body)
      environment["CONTENT_LENGTH"] = body.bytesize.to_s
      environment["CONTENT_TYPE"] = "application/json"
      environment["ORIGINAL_FULLPATH"] = Discourse.base_path + path
      environment["ORIGINAL_FULLPATH"] += "?#{environment["QUERY_STRING"]}" if environment[
        "QUERY_STRING"
      ].present?
      environment["action_dispatch.parameter_filter"] = Array(
        environment["action_dispatch.parameter_filter"],
      ) + parameters.keys
      native_request = ActionDispatch::Request.new(environment)
      native_request.path_parameters = {
        controller: "admin/site_settings",
        action: action.to_s,
      }.merge(route_parameters)
      set_request!(native_request)
      request.format = :json
      self.params = ActionController::Parameters.new(request.parameters)
    end

    def ensure_native_admin_constraints
      unless StaffConstraint.new.matches?(request) && AdminConstraint.new.matches?(request)
        raise Discourse::NotFound
      end
    end
  end
end
