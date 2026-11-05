module DiscourseGraphQL
  module Loaders
    class TopicAuthorization < GraphQL::Dataloader::Source
      def initialize(guardian:)
        @guardian = guardian
      end

      def fetch(topic_ids)
        permitted_ids = @guardian.can_see_topic_ids(topic_ids: topic_ids).to_set
        topic_ids.map { |topic_id| permitted_ids.include?(topic_id) }
      end
    end
  end
end
