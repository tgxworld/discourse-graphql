module DiscourseGraphQL
  class DirectUploadCompletion < ::UploadsController
    include NativeRequest

    def call(parameters:)
      self.params = ActionController::Parameters.new(parameters)
      process(:complete_external_upload)
      ExternalUploadResponse.new(response).completion_payload
    end
  end
end
