module DiscourseGraphQL
  module Types
    class TopicTimingsInput < BaseInputObject
      argument :topic_id, ID, required: true
      argument :topic_time_ms, Int, required: true
      argument :timings, [PostTimingInput], required: true
    end
  end
end
