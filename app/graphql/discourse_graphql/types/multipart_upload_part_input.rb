module DiscourseGraphQL
  module Types
    class MultipartUploadPartInput < BaseInputObject
      argument :part_number, Int, required: true
      argument :etag, String, required: true
    end
  end
end
