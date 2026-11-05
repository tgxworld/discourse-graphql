module DiscourseGraphQL
  module DraftParameters
    def self.validate!(key:, sequence: nil)
      raise Discourse::InvalidParameters if key.blank? || key.size > 40
      if !sequence.nil? && !sequence.between?(0, (2**63) - 1)
        raise Discourse::InvalidParameters
      end
    end
  end
end
