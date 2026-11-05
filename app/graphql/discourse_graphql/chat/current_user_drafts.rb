module DiscourseGraphQL
  module Chat
    class CurrentUserDrafts < ::SessionController
      include NativeRequest

      def call
        self.params = ActionController::Parameters.new
        process(:current)
        result = NativeResponse.new(response)
        result.raise_error!
        result.payload.dig("current_user", "chat_drafts")
      end

      private

      def serialize_data(object, serializer, options = nil)
        return super unless serializer == ::CurrentUserSerializer

        super(
          object,
          serializer,
          NativeSerialization.options(options: options || {}, fields: [:chat_drafts]),
        )
      end
    end
  end
end
