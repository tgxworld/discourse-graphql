module DiscourseGraphQL
  class NotificationReading < ::NotificationsController
    include NativeRequest

    def self.requires_login_arg
      superclass.requires_login_arg
    end

    def call(id: nil)
      self.params = ActionController::Parameters.new(id.nil? ? {} : { id: id })
      process(:mark_read)
      result = NativeResponse.new(response)
      { success: result.successful?, errors: result.errors }
    end
  end
end
