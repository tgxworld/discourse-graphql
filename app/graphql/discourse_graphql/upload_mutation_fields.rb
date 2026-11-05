module DiscourseGraphQL
  module UploadMutationFields
    def self.included(type)
      type.field :create_upload, Types::UploadPayloadType, null: true, complexity: 1000 do
        argument :input, Types::CreateUploadInput, required: true
      end
      type.field :create_direct_upload,
                 Types::ExternalUploadPayloadType,
                 null: true,
                 complexity: 1000 do
        argument :input, Types::CreateExternalUploadInput, required: true
      end
      type.field :create_multipart_upload,
                 Types::ExternalUploadPayloadType,
                 null: true,
                 complexity: 1000 do
        argument :input, Types::CreateExternalUploadInput, required: true
      end
      type.field :presign_upload_parts, Types::UploadPartsPayloadType, null: true do
        argument :unique_identifier, GraphQL::Types::ID, required: true
        argument :part_numbers, [Integer], required: true
        complexity ->(_context, arguments, child) do
                     1000 + arguments[:part_numbers].size.clamp(0, 100) * 20 + child
                   end
      end
      type.field :complete_direct_upload, Types::UploadPayloadType, null: true, complexity: 2000 do
        argument :input, Types::CompleteUploadInput, required: true
      end
      type.field :complete_multipart_upload, Types::UploadPayloadType, null: true do
        argument :input, Types::CompleteMultipartUploadInput, required: true
        complexity ->(_context, arguments, child) do
                     2000 + (arguments[:input][:parts].size.clamp(0, 10_000) / 10.0).ceil + child
                   end
      end
      type.field :abort_multipart_upload, Types::ActionPayloadType, null: true, complexity: 1000 do
        argument :external_upload_identifier, GraphQL::Types::ID, required: true
      end
    end

    def create_upload(input:)
      parameters = upload_options(input.to_h)
      if parameters[:file].present? == parameters[:url].present? ||
           parameters[:url]&.bytesize.to_i > 4096
        raise Discourse::InvalidParameters
      end
      perform_upload(adapter: UploadCreation, parameters: parameters)
    end

    def create_direct_upload(input:)
      parameters = external_upload_parameters(input)
      parameters[:type] = parameters.delete(:upload_type)
      perform_upload(adapter: DirectUploadCreation, parameters: parameters)
    end

    def create_multipart_upload(input:)
      perform_upload(
        adapter: MultipartUploadCreation,
        parameters: external_upload_parameters(input),
      )
    end

    def presign_upload_parts(unique_identifier:, part_numbers:)
      validate_upload_identifier!(unique_identifier)
      if !part_numbers.size.between?(1, 100) || part_numbers.uniq.size != part_numbers.size ||
           part_numbers.any? { |number| !number.between?(1, 10_000) }
        raise Discourse::InvalidParameters
      end
      perform_upload(
        adapter: UploadPartSigning,
        parameters: {
          unique_identifier: unique_identifier,
          part_numbers: part_numbers,
        },
      )
    end

    def complete_direct_upload(input:)
      parameters = upload_options(input.to_h)
      validate_upload_identifier!(parameters[:unique_identifier])
      perform_upload(adapter: DirectUploadCompletion, parameters: parameters)
    end

    def complete_multipart_upload(input:)
      parameters = upload_options(input.to_h)
      validate_upload_identifier!(parameters[:unique_identifier])
      parts = parameters.fetch(:parts)
      if !parts.size.between?(1, 10_000) ||
           parts.map { |part| part[:part_number] }.uniq.size != parts.size ||
           parts.any? { |part|
             !part[:part_number].between?(1, 10_000) || part[:etag].blank? ||
               part[:etag].bytesize > 2048
           }
        raise Discourse::InvalidParameters
      end
      perform_upload(adapter: MultipartUploadCompletion, parameters: parameters)
    end

    def abort_multipart_upload(external_upload_identifier:)
      validate_upload_identifier!(external_upload_identifier)
      perform_upload(
        adapter: MultipartUploadCancellation,
        parameters: {
          external_upload_identifier: external_upload_identifier,
        },
      )
    end

    private

    def external_upload_parameters(input)
      parameters = input.to_h
      size = parameters.delete(:file_size_bytes)
      if !size.between?(1, (2**63) - 1) || parameters[:file_name].bytesize > 1024 ||
           parameters[:upload_type].bytesize > 100 ||
           parameters[:sha1_checksum]&.bytesize.to_i > 128
        raise Discourse::InvalidParameters
      end
      parameters[:file_size] = size
      checksum = parameters.delete(:sha1_checksum)
      parameters[:metadata] = { "sha1-checksum" => checksum } unless checksum.nil?
      parameters
    end

    def upload_options(parameters)
      %i[pasted for_private_message for_site_setting].each do |key|
        parameters[key] = parameters[key].to_s unless parameters[key].nil?
      end
      parameters
    end

    def validate_upload_identifier!(identifier)
      raise Discourse::InvalidParameters if identifier.blank? || identifier.bytesize > 4096
    end

    def perform_upload(adapter:, parameters:)
      context.dataloader.clear_cache
      adapter.new(request: context[:request], request_method: "POST").call(parameters: parameters)
    ensure
      context.dataloader.clear_cache
    end
  end
end
