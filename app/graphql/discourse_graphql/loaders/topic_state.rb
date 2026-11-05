module DiscourseGraphQL
  module Loaders
    class TopicState < GraphQL::Dataloader::Source
      def initialize(user:)
        @user = user
      end

      def fetch(topics)
        lookup = TopicUser.lookup_for(@user, topics)
        topics.map { |topic| lookup[topic.id] }
      end
    end
  end
end
