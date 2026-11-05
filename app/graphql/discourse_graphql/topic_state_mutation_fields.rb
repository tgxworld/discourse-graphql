module DiscourseGraphQL
  module TopicStateMutationFields
    def self.included(type)
      type.field :record_topic_timings, Types::ActionPayloadType, null: true do
        argument :input, Types::TopicTimingsInput, required: true
        complexity ->(_context, arguments, child_complexity) do
                     1000 + arguments[:input][:timings].size.clamp(0, 50) * 10 + child_complexity
                   end
      end
      type.field :update_topic_notifications,
                 Types::ActionPayloadType,
                 null: true,
                 complexity: 1000 do
        argument :topic_id, GraphQL::Types::ID, required: true
        argument :level, Types::TopicNotificationLevel, required: true
      end
      type.field :reset_topic_reading, Types::ActionPayloadType, null: true, complexity: 1000 do
        argument :topic_id, GraphQL::Types::ID, required: true
        argument :last_post_only,
                 GraphQL::Types::Boolean,
                 required: false,
                 default_value: false,
                 replace_null_with_default: true
      end
    end

    def record_topic_timings(input:)
      parameters = input.to_h
      timings = parameters.delete(:timings)
      if parameters[:topic_time_ms].negative? || timings.size > 50 ||
           timings.any? { |entry| entry[:milliseconds].negative? || entry[:post_number] < 1 } ||
           timings.map { |entry| entry[:post_number] }.uniq.size != timings.size
        raise Discourse::InvalidParameters
      end
      parameters[:topic_time] = parameters.delete(:topic_time_ms)
      parameters[:timings] = timings.to_h do |entry|
        [entry[:post_number].to_s, entry[:milliseconds]]
      end
      change_topic_state(adapter: TopicTimings, parameters: parameters, request_method: "POST")
    end

    def update_topic_notifications(topic_id:, level:)
      change_topic_state(
        adapter: TopicNotifications,
        parameters: {
          topic_id: topic_id,
          notification_level: level,
        },
        request_method: "POST",
      )
    end

    def reset_topic_reading(topic_id:, last_post_only:)
      parameters = { topic_id: topic_id }
      parameters[:last] = 1 if last_post_only
      change_topic_state(
        adapter: TopicReadingReset,
        parameters: parameters,
        request_method: "DELETE",
      )
    end

    private

    def change_topic_state(adapter:, parameters:, request_method:)
      context.dataloader.clear_cache
      adapter.new(request: context[:request], request_method: request_method).call(
        parameters: parameters,
      )
    ensure
      context.dataloader.clear_cache
    end
  end
end
