module DiscourseGraphQL
  class UploadPartSigning < ::UploadsController
    include NativeRequest

    def call(parameters:)
      self.params = ActionController::Parameters.new(parameters)
      process(:batch_presign_multipart_parts)
      ExternalUploadResponse.new(response).parts_payload
    end
  end
end
