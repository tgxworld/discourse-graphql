module DiscourseGraphQL
  module Types
    class BaseField < GraphQL::Schema::Field
      argument_class Types::BaseArgument

      def initialize(*arguments, native_archive_action: nil, **options, &block)
        @native_archive_action = native_archive_action
        super(*arguments, **options, &block)
      end

      def allows_archived_requests?
        return false unless @native_archive_action
        controller, action = @native_archive_action
        controller.allowed_when_archived?(action)
      end
    end
  end
end
