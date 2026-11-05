module DiscourseGraphQL
  class ExternalUploadResponse < NativeResponse
    def ticket_payload
      ticket = payload.merge("signed_headers" => (payload["signed_headers"] || {}).map { |name, value| { name: name, value: value } }) if successful?
      action_payload.merge(ticket: ticket)
    end

    def completion_payload
      action_payload.merge(upload: successful? && payload["id"] ? payload : nil)
    end

    def parts_payload
      parts = payload.fetch("presigned_urls").map { |number, url| { part_number: number.to_i, url: url } } if successful?
      action_payload.merge(parts: parts)
    end
  end
end
