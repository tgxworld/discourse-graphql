module DiscourseGraphQL
  module SiteSettingParameters
    def self.validate_name!(name)
      raise Discourse::InvalidParameters if name.blank? || name.bytesize > 128
    end

    def self.validate_filters!(names:, categories:, plugin:)
      [names, categories].compact.each do |values|
        raise Discourse::InvalidParameters if values.size > 100
        values.each { |value| validate_name!(value) }
      end
      validate_name!(plugin) unless plugin.nil?
    end
  end
end
