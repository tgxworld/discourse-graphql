module DiscourseGraphQL
  class BookmarkListSerializer < ::UserBookmarkListSerializer
    def bookmarks
      super.map do |serializer|
        selected = NativeSerialization.options(options: serializer.options, fields: options.fetch(:bookmark_fields))
        attributes = serializer.class.new(serializer.object, selected).as_json
        metadata_options = NativeSerialization.options(options: selected, fields: [:auto_delete_preference])
        if metadata_options[:only].present?
          attributes.merge!(::TopicViewBookmarkSerializer.new(serializer.object, metadata_options).as_json)
        end
        attributes
      end
    end
  end
end
