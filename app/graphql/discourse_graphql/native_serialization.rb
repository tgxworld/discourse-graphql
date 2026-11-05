module DiscourseGraphQL
  module NativeSerialization
    def self.options(options:, fields:)
      selected = options.key?(:only) ? fields & Array(options[:only]) : fields
      options.merge(only: selected)
    end
  end
end
