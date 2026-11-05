module DiscourseGraphQL
  module Types
    class CompleteMultipartUploadInput < CompleteUploadInput
      argument :parts, [MultipartUploadPartInput], required: true
    end
  end
end
