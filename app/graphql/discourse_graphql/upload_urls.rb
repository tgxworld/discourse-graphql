module DiscourseGraphQL
  class UploadUrls < ::UploadsController
    include NativeRequest

    def call(short_urls:)
      if short_urls.size > 100 || short_urls.any? { |url| url.bytesize > 4096 }
        raise Discourse::InvalidParameters
      end
      self.params = ActionController::Parameters.new(short_urls: short_urls)
      process(:lookup_urls)
      result = NativeResponse.new(response)
      result.raise_error!
      result.payload
    end
  end
end
