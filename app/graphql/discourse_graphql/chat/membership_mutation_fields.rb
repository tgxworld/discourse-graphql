module DiscourseGraphQL
  module Chat
    module MembershipMutationFields
      def self.included(type)
        %i[join_chat_channel leave_chat_channel unfollow_chat_channel].each do |name|
          type.field name, MembershipPayloadType, null: true, complexity: 1000 do
            extras [:lookahead]
            argument :channel_id, GraphQL::Types::ID, required: true
          end
        end
        type.field :star_chat_channel, MembershipPayloadType, null: true, complexity: 1000 do
          extras [:lookahead]
          argument :channel_id, GraphQL::Types::ID, required: true
          argument :starred, GraphQL::Types::Boolean, required: true
        end
        type.field :update_chat_notifications, MembershipPayloadType, null: true, complexity: 1000 do
          extras [:lookahead]
          argument :input, NotificationInput, required: true
        end
        type.field :mark_chat_read, MembershipPayloadType, null: true, complexity: 1000 do
          extras [:lookahead]
          argument :channel_id, GraphQL::Types::ID, required: true
          argument :message_id, GraphQL::Types::ID, required: true
        end
        type.field :mark_all_chat_read, MembershipPayloadType, null: true, complexity: 4000, extras: [:lookahead]
      end

      def self.capability
        {
          id: "chat.membershipAndReading",
          available: Discourse.plugins_by_name.fetch("chat").enabled?,
          query_fields: [],
          mutation_fields: %w[joinChatChannel leaveChatChannel unfollowChatChannel starChatChannel updateChatNotifications markChatRead markAllChatRead],
        }
      end

      def join_chat_channel(channel_id:, lookahead:)
        perform_membership(adapter: JoinChannel, parameters: { channel_id: channel_id }, request_method: "POST", lookahead: lookahead)
      end

      def leave_chat_channel(channel_id:, lookahead:)
        perform_membership(adapter: LeaveChannel, parameters: { channel_id: channel_id }, request_method: "DELETE", lookahead: lookahead)
      end

      def unfollow_chat_channel(channel_id:, lookahead:)
        perform_membership(adapter: UnfollowChannel, parameters: { channel_id: channel_id }, request_method: "DELETE", lookahead: lookahead)
      end

      def star_chat_channel(channel_id:, starred:, lookahead:)
        perform_membership(adapter: StarChannel, parameters: { channel_id: channel_id, starred: starred }, request_method: "PUT", lookahead: lookahead)
      end

      def update_chat_notifications(input:, lookahead:)
        parameters = input.to_h.compact
        channel_id = parameters.delete(:channel_id)
        perform_membership(adapter: UpdateNotifications, parameters: { channel_id: channel_id, notifications_settings: parameters }, request_method: "PUT", lookahead: lookahead)
      end

      def mark_chat_read(channel_id:, message_id:, lookahead:)
        perform_membership(adapter: MarkRead, parameters: { channel_id: channel_id, message_id: message_id }, request_method: "PUT", lookahead: lookahead)
      end

      def mark_all_chat_read(lookahead:)
        perform_membership(adapter: MarkAllRead, parameters: {}, request_method: "PUT", lookahead: lookahead)
      end

      private

      def perform_membership(adapter:, parameters:, request_method:, lookahead:)
        Extensions.ensure_enabled!("chat")
        context.dataloader.clear_cache
        fields = lookahead.selection(:membership).selections.map { |selection| selection.field.method_sym }
        adapter.new(request: context[:request], request_method: request_method).call(parameters: parameters, fields: fields)
      ensure
        context.dataloader.clear_cache
      end
    end
  end
end
