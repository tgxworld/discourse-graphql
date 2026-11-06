module DiscourseGraphQL
  class MultipartUploadCancellation < ::UploadsController
    include NativeRequest

    def call(parameters:)
      self.params = ActionController::Parameters.new(parameters)
      process(:abort_multipart)
      ExternalUploadResponse.new(response).action_payload
    end
  end
end
