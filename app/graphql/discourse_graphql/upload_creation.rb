module DiscourseGraphQL
  class UploadCreation < ::UploadsController
    include NativeRequest

    def call(parameters:)
      self.params = ActionController::Parameters.new(parameters)
      process(:create)
      result = NativeResponse.new(response)
      result.action_payload.merge(upload: result.successful? ? result.payload : nil)
    end

    def create
      file = params[:file]
      if file
        temporary_file =
          Tempfile.new(
            ["discourse-graphql-upload", File.extname(file.original_filename)[0, 129]],
            binmode: true,
          )
        File.open(file.tempfile.path, "rb") { |source| IO.copy_stream(source, temporary_file) }
        temporary_file.rewind
        params[:file] = ActionDispatch::Http::UploadedFile.new(
          tempfile: temporary_file,
          filename: file.original_filename,
          type: file.content_type,
        )
      end
      super
    ensure
      temporary_file&.close!
    end
  end
end
