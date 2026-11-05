module DiscourseGraphQL
  module Types
    class UploadHeaderType < BaseObject
      field :name, String, null: false
      field :value, String, null: false
    end
  end
end
