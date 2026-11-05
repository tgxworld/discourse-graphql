module DiscourseGraphQL
  module Loaders
    class RecordLoader < GraphQL::Dataloader::ActiveRecordSource
      def fetch(ids)
        records = super
        associations =
          if @model_class == Topic
            %i[category shared_draft]
          elsif @model_class == Post
            [:user, { topic: %i[category shared_draft] }]
          end

        if associations
          ActiveRecord::Associations::Preloader.new(
            records: records.compact,
            associations: associations,
          ).call
        end

        records
      end
    end
  end
end
