module DiscourseGraphQL
  module Chat
    module MessageInputLimits
      def self.validate_upload_ids!(ids)
        raise Discourse::InvalidParameters if ids && ids.size > 200
      end
    end
  end
end
