module DiscourseGraphQL
  module SiteSettingMetadataValues
    def self.wire(value)
      return nil if value.nil?
      unless value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false
        raise Discourse::InvalidParameters
      end
      value.to_s
    end

    def self.list(values)
      return nil if values.nil?
      raise Discourse::InvalidParameters unless values.is_a?(Array) && values.size <= 100
      values.map { |value| wire(value) }
    end
  end
end
