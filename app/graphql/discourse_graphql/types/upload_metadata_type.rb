module DiscourseGraphQL
  module Types
    class UploadMetadataType < BaseObject
      field :original_filename, String, null: true, hash_key: "original_filename"
      field :width, Int, null: true, hash_key: "width"
      field :height, Int, null: true, hash_key: "height"
      field :human_filesize, String, null: true, hash_key: "human_filesize"
    end
  end
end
