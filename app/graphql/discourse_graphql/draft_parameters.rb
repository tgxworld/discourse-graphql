module DiscourseGraphQL
  module DraftParameters
    def self.validate!(key:, sequence: nil)
      raise Discourse::InvalidParameters if key.blank? || key.size > 40
      raise Discourse::InvalidParameters if !sequence.nil? && !sequence.between?(0, (2**63) - 1)
    end
  end
end
