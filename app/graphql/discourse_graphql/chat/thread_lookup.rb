module DiscourseGraphQL
  module Chat
    class ThreadLookup < ::Chat::Api::ChannelThreadsController
      include NativeRequest

      def call(parameters:, fields:)
        @thread_fields = fields
        self.params = ActionController::Parameters.new(parameters)
        process(:show)
        result = NativeResponse.new(response)
        result.raise_error!
        result.payload.fetch("thread")
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
