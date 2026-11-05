module DiscourseGraphQL
  class MultipartUploadCompletion < ::UploadsController
    include NativeRequest

    def call(parameters:)
      self.params = ActionController::Parameters.new(parameters)
      process(:complete_multipart)
      ExternalUploadResponse.new(response).completion_payload
    end
  end
end
