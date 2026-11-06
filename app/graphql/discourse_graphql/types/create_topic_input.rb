module DiscourseGraphQL
  module Types
    class CreateTopicInput < BaseInputObject
      argument :title, String, required: true
      argument :raw, String, required: true
      argument :category_id, ID, required: false
      argument :tags, [String], required: false
      argument :locale, String, required: false
    end
  end
end
