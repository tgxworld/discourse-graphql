module DiscourseGraphQL
  class UploadMetadata < ::UploadsController
    include NativeRequest

    def call(url:)
      raise Discourse::InvalidParameters if url.blank? || url.bytesize > 4096
      self.params = ActionController::Parameters.new(url: url)
      process(:metadata)
      result = NativeResponse.new(response)
      result.raise_error!
      result.payload
    end
  end
end
