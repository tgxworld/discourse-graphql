module DiscourseGraphQL
  module Types
    class SiteSettingUploadType < BaseObject
      field :original_filename, String, null: true, hash_key: "original_filename"
      field :human_filesize, String, null: true, hash_key: "human_filesize"
      field :width, Integer, null: true, hash_key: "width"
      field :height, Integer, null: true, hash_key: "height"
    end
  end
end
