module DiscourseGraphQL
  module Types
    class UploadPartUrlType < BaseObject
      field :part_number, Int, null: false
      field :url, String, null: false
    end
  end
end
