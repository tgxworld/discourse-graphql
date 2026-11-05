module DiscourseGraphQL
  module Chat
    class ThreadCreation < ::Chat::Api::ChannelThreadsController
      include NativeRequest

      def call(parameters:, fields:)
        @thread_fields = fields
        self.params = ActionController::Parameters.new(parameters)
        process(:create)
        result = NativeResponse.new(response)
        {
          success: result.successful?,
          thread: result.successful? ? result.payload : nil,
          errors: result.errors,
        }
      end

      private

      def serialize_data(object, serializer, options = nil)
        return super unless serializer == ::Chat::ThreadSerializer
        native = serializer.new(object, { scope: guardian }.merge(options || {}))
        ThreadFieldSelection.select(serializer: native, fields: @thread_fields).as_json
      end
    end
  end
end
