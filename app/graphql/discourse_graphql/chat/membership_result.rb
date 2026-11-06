module DiscourseGraphQL
  module Chat
    module MembershipResult
      private

      def membership_result
        result = NativeResponse.new(response)
        {
          success: result.successful?,
          membership: result.payload["membership"],
          updated_count: result.payload["updated_memberships"]&.size,
          errors: result.errors,
        }
      end

      def render_serialized(object, serializer, options = nil)
        unless serializer == ::Chat::UserChannelMembershipSerializer ||
                 serializer == ::Chat::BaseThreadMembershipSerializer
          return super
        end

        super(
          object,
          serializer,
          NativeSerialization.options(options: options || {}, fields: @membership_fields),
        )
      end
    end
  end
end
