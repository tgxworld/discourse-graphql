module DiscourseGraphQL
  class DirectUploadCreation < ::UploadsController
    include NativeRequest

    def call(parameters:)
      self.params = ActionController::Parameters.new(parameters)
      process(:generate_presigned_put)
      ExternalUploadResponse.new(response).ticket_payload
    end
  end
end
