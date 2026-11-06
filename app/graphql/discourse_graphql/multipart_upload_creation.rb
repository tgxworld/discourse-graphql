module DiscourseGraphQL
  class MultipartUploadCreation < ::UploadsController
    include NativeRequest

    def call(parameters:)
      self.params = ActionController::Parameters.new(parameters)
      process(:create_multipart)
      ExternalUploadResponse.new(response).ticket_payload
    end
  end
end
