module DiscourseGraphQL
  module Types
    class DraftContentInput < BaseInputObject
      argument :reply, String, required: false
      argument :title, String, required: false
      argument :action, String, required: false
      argument :category_id, GraphQL::Types::BigInt, required: false
      argument :post_id, GraphQL::Types::BigInt, required: false
      argument :archetype_id, String, required: false
      argument :recipients, String, required: false
      argument :whisper, Boolean, required: false
      argument :composer_time_ms, GraphQL::Types::BigInt, required: false
      argument :typing_time_ms, GraphQL::Types::BigInt, required: false
      argument :original_text, String, required: false
      argument :original_title, String, required: false
      argument :locale, String, required: false
      argument :reply_to_post_number, Int, required: false
      argument :admin_onboarding_topic_option, String, required: false
      argument :tags, [DraftTagInput], required: false
      argument :original_tags, [DraftTagInput], required: false
      argument :reply_to_user, DraftReplyUserInput, required: false
    end
  end
end
