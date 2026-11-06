module DiscourseGraphQL
  module Types
    class CreatePostInput < BaseInputObject
      argument :topic_id, ID, required: true
      argument :raw, String, required: true
      argument :reply_to_post_number, Int, required: false
      argument :auto_track, Boolean, required: false
      argument :locale, String, required: false
    end
  end
end
