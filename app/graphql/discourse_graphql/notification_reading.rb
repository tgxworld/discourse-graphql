module DiscourseGraphQL
  class NotificationReading < ::NotificationsController
    include NativeRequest

    def call(id: nil)
      self.params = ActionController::Parameters.new(id.nil? ? {} : { id: id })
      process(:mark_read)
      NativeResponse.new(response).action_payload
    end
  end
end
