module DiscourseGraphQL
  module Chat
    module MessageFlagPermissions
      def prepare_graphql_flag_category(channel_id:)
        @graphql_flag_channel_id = channel_id.to_s
      end

      def can_flag_in_chat_channel?(chat_channel, post_allowed_category_ids: nil)
        if post_allowed_category_ids.nil? && chat_channel.id.to_s == @graphql_flag_channel_id &&
             authenticated? && !is_anonymous? && chat_channel.chatable.is_a?(::Category)
          @graphql_post_allowed_category_ids ||=
            ::Category.post_create_allowed(self).where(id: chat_channel.chatable_id).pluck(:id)
          post_allowed_category_ids = @graphql_post_allowed_category_ids
        end
        super(chat_channel, post_allowed_category_ids: post_allowed_category_ids)
      end
    end
  end
end
