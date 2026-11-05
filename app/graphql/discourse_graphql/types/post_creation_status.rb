module DiscourseGraphQL
  module Types
    class PostCreationStatus < BaseEnum
      value "PUBLISHED"
      value "PENDING"
      value "HANDLED"
      value "FAILED"
    end
  end
end
