module DiscourseGraphQL
  class MultipartRequest
    MAX_FILES = RequestBodyLimit::MAX_FILES
    MAX_FILE_BYTES = 100 * 1024 * 1024

    def self.parameters(parameters)
      return parameters unless parameters.key?(:operations) || parameters.key?(:map)
      operations_text = parameters[:operations]
      map_text = parameters[:map]
      unless operations_text.is_a?(String) && map_text.is_a?(String) &&
               operations_text.bytesize + map_text.bytesize <= RequestBodyLimit::MAX_DOCUMENT_BYTES
        raise Discourse::InvalidParameters
      end

      operations = JSON.parse(operations_text)
      mapping = JSON.parse(map_text)
      unless operations.is_a?(Hash) && operations["variables"].is_a?(Hash) && mapping.is_a?(Hash) &&
               mapping.size.between?(1, MAX_FILES)
        raise Discourse::InvalidParameters
      end
      extra_keys = parameters.keys - %w[operations map controller action format]
      raise Discourse::InvalidParameters unless extra_keys.sort == mapping.keys.sort

      paths = []
      total_bytes = 0
      mapping.each do |part, targets|
        file = parameters[part]
        unless file.is_a?(ActionDispatch::Http::UploadedFile) && targets.is_a?(Array) &&
                 targets.size.between?(1, 10)
          raise Discourse::InvalidParameters
        end
        total_bytes += file.size
        raise Discourse::InvalidParameters if total_bytes > MAX_FILE_BYTES
        targets.each do |path|
          unless path.is_a?(String) && path.bytesize <= 1024 && !paths.include?(path)
            raise Discourse::InvalidParameters
          end
          segments = path.split(".", -1)
          unless segments.shift == "variables" && segments.size.between?(1, 12)
            raise Discourse::InvalidParameters
          end
          target = operations.fetch("variables")
          segments.each_with_index do |segment, index|
            key =
              (
                if target.is_a?(Array) && segment.match?(/\A(?:0|[1-9][0-9]*)\z/)
                  segment.to_i
                else
                  segment
                end
              )
            valid =
              (
                if target.is_a?(Hash)
                  target.key?(key)
                else
                  target.is_a?(Array) && key.is_a?(Integer) && key < target.size
                end
              )
            raise Discourse::InvalidParameters unless valid
            if index == segments.size - 1
              raise Discourse::InvalidParameters unless target[key].nil?
              target[key] = file
            else
              target = target[key]
            end
          end
          paths << path
        end
      end
      ActionController::Parameters.new(operations)
    end
  end
end
