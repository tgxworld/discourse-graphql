module DiscourseGraphQL
  module Types
    class DraftContentType < BaseObject
      field :reply, String, null: true, hash_key: "reply"
      field :title, String, null: true, hash_key: "title"
      field :action, String, null: true, hash_key: "action"
      field :category_id, GraphQL::Types::BigInt, null: true, hash_key: "categoryId"
      field :post_id, GraphQL::Types::BigInt, null: true, hash_key: "postId"
      field :archetype_id, String, null: true, hash_key: "archetypeId"
      field :recipients, String, null: true, hash_key: "recipients"
      field :whisper, Boolean, null: true, hash_key: "whisper"
      field :composer_time_ms, GraphQL::Types::BigInt, null: true, hash_key: "composerTime"
      field :typing_time_ms, GraphQL::Types::BigInt, null: true, hash_key: "typingTime"
      field :original_text, String, null: true, hash_key: "original_text"
      field :original_title, String, null: true, hash_key: "original_title"
      field :locale, String, null: true, hash_key: "locale"
      field :reply_to_post_number, Int, null: true, hash_key: "reply_to_post_number"
      field :admin_onboarding_topic_option, String, null: true, hash_key: "adminOnboardingTopicOption"
      field :tags, [DraftTagType], null: true, hash_key: "tags", complexity: ->(_context, _arguments, child) { DraftContent::MAX_TAGS * child }
      field :original_tags, [DraftTagType], null: true, hash_key: "original_tags", complexity: ->(_context, _arguments, child) { DraftContent::MAX_TAGS * child }
      field :reply_to_user, DraftReplyUserType, null: true, hash_key: "reply_to_user"
      field :unmapped_fields, [String], null: false, hash_key: "unmapped_fields", complexity: DraftContent::MAX_UNMAPPED_FIELDS
    end
  end
end
