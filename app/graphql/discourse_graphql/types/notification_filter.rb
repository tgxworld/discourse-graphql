module DiscourseGraphQL
  module Types
    class NotificationFilter < BaseEnum
      value "ALL", value: nil
      value "READ", value: "read"
      value "UNREAD", value: "unread"
    end
  end
end
