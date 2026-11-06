module DiscourseGraphQL
  module Chat
    module ReactionInputLimits
      def self.validate_emoji_size!(emoji)
        raise Discourse::InvalidParameters if emoji && emoji.bytesize > 512
      end
    end
  end
end
