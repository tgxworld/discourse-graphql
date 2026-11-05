module DiscourseGraphQL
  class RequestBodyLimit
    MAX_DOCUMENT_BYTES = 1024 * 1024
    MAX_BODY_BYTES = 101 * 1024 * 1024
    MAX_FILES = 10

    class Exceeded < StandardError
    end

    class InvalidMultipart < StandardError
    end

    class MultipartParameters < SimpleDelegator
      def initialize(parser)
        super(parser)
        @part_names = Set.new
        @text_bytes = 0
      end

      def normalize_params(parameters, name, value, depth)
        raise InvalidMultipart unless @part_names.add?(name)
        @text_bytes += value.bytesize if value.is_a?(String)
        raise InvalidMultipart if @text_bytes > MAX_DOCUMENT_BYTES
        __getobj__.normalize_params(parameters, name, value, depth)
      end
    end

    class Input
      attr_reader :exceeded

      def initialize(source:, limit_bytes:)
        @source = source
        @limit_bytes = limit_bytes
        @read_bytes = 0
        @exceeded = false
      end

      def read(length = nil, buffer = nil)
        remaining_bytes = @limit_bytes - @read_bytes + 1
        read_length = length.nil? ? remaining_bytes : [length, remaining_bytes].min
        account(@source.read(read_length, buffer))
      end

      def gets
        account(@source.gets(@limit_bytes - @read_bytes + 1))
      end

      def each
        return enum_for(:each) unless block_given?
        while (line = gets)
          yield line
        end
      end

      def rewind
        @source.rewind
        @read_bytes = 0
      end

      private

      def account(value)
        @read_bytes += value.bytesize if value
        if @read_bytes > @limit_bytes
          @exceeded = true
          raise Exceeded
        end
        value
      end
    end

    def initialize(app)
      @app = app
    end

    def call(environment)
      path = environment["PATH_INFO"].to_s
      return @app.call(environment) unless path.match?(%r{(?:\A|/)discourse-graphql/graphql(?:\.[^/]+)?/?\z})

      environment["action_dispatch.parameter_filter"] = Array(environment["action_dispatch.parameter_filter"]) + %i[query variables operations]

      multipart = environment["CONTENT_TYPE"].to_s.match?(%r{\Amultipart/form-data(?:;|\z)}i)
      limit_bytes = multipart ? MAX_BODY_BYTES : MAX_DOCUMENT_BYTES
      return too_large if environment["CONTENT_LENGTH"].to_i > limit_bytes

      input = Input.new(source: environment.fetch("rack.input"), limit_bytes: limit_bytes)
      environment["rack.input"] = input
      files = []
      if multipart
        factory = environment["rack.multipart.tempfile_factory"] || Rack::Multipart::Parser::TEMPFILE_FACTORY
        environment["rack.multipart.tempfile_factory"] = lambda do |filename, content_type|
          raise InvalidMultipart if files.size >= MAX_FILES
          factory.call(filename, content_type).tap { |file| files << file }
        end
        parameters = Rack::Multipart.parse_multipart(environment, MultipartParameters.new(Rack::Utils.default_query_parser))
        environment["rack.request.form_hash"] = parameters if parameters
        environment["rack.request.form_input"] = input if parameters
      end

      status, headers, body = @app.call(environment)
      if input.exceeded
        body.close if body.respond_to?(:close)
        return too_large
      end
      response_body = Rack::BodyProxy.new(body) { files.each(&:close!) }
      handed_to_body = true
      [status, headers, response_body]
    rescue Exceeded
      too_large
    rescue InvalidMultipart, EOFError, Rack::QueryParser::ParameterTypeError, Rack::QueryParser::InvalidParameterError, Rack::QueryParser::ParamsTooDeepError, Rack::Multipart::MultipartPartLimitError, Rack::Multipart::MultipartTotalPartLimitError
      return too_large if input&.exceeded
      error_response(status: 400, key: "invalid_request", code: "BAD_REQUEST")
    ensure
      files&.each(&:close!) unless handed_to_body
    end

    private

    def too_large
      error_response(status: 413, key: "request_too_large", code: "PAYLOAD_TOO_LARGE")
    end

    def error_response(status:, key:, code:)
      payload = { errors: [{ message: I18n.t("discourse_graphql.errors.#{key}"), extensions: { code: code } }] }
      [status, { "Content-Type" => "application/json", "Cache-Control" => "no-store" }, [JSON.generate(payload)]]
    end
  end
end
