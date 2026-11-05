module DiscourseGraphQL
  module Types
    class PostTimingInput < BaseInputObject
      argument :post_number, Int, required: true
      argument :milliseconds, Int, required: true
    end
  end
end
