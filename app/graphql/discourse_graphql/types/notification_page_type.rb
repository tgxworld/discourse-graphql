module DiscourseGraphQL
  module Types
    class NotificationPageType < BaseObject
      field :nodes, [NotificationType], null: false
      field :seen_notification_id, ID, null: false
      field :page_info, PageInfoType, null: false
    end
  end
end
