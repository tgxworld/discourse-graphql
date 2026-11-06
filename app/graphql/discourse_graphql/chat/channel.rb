module DiscourseGraphQL
  module Chat
    class Channel < ::Chat::Api::ChannelsController
      include NativeRequest

      def call(channel_id:, fields:)
        @fields = fields
        self.params = ActionController::Parameters.new(channel_id: channel_id)
        process(:show)
        result = NativeResponse.new(response)
        result.raise_error!
        result.payload.fetch("channel")
      end

      private

      def render_serialized(object, serializer, options = nil)
        return super unless serializer == ::Chat::ChannelSerializer

        super(
          object,
          serializer,
          NativeSerialization.options(options: options || {}, fields: @fields),
        )
      end
    end
  end
end
