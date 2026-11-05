module DiscourseGraphQL
  class DraftContent
    MAX_TAGS = 100
    MAX_UNMAPPED_FIELDS = 100
    NATIVE_KEYS = {
      reply: "reply", title: "title", action: "action", category_id: "categoryId",
      post_id: "postId", archetype_id: "archetypeId", recipients: "recipients",
      whisper: "whisper", composer_time_ms: "composerTime", typing_time_ms: "typingTime",
      original_text: "original_text", original_title: "original_title",
      tags: "tags", original_tags: "original_tags", locale: "locale",
      reply_to_post_number: "reply_to_post_number", reply_to_user: "reply_to_user",
      admin_onboarding_topic_option: "adminOnboardingTopicOption",
    }.freeze
    ALIASES = { "originalText" => "original_text", "originalTitle" => "original_title", "originalTags" => "original_tags" }.freeze
    TAG_KEYS = %w[id name slug isNew].freeze
    REPLY_USER_KEYS = %w[id username name avatar_template].freeze
    private_constant :NATIVE_KEYS, :ALIASES, :TAG_KEYS, :REPLY_USER_KEYS

    def self.encode(input)
      content = input.to_h.to_h { |key, value| [NATIVE_KEYS.fetch(key), value] }
      %w[tags original_tags].each do |key|
        next if content[key].nil?
        raise Discourse::InvalidParameters if content[key].size > MAX_TAGS
        content[key] = content[key].map do |tag|
          if tag[:format] == "NAME"
            raise Discourse::InvalidParameters unless tag[:name].is_a?(String)
            tag[:name]
          else
            tag.except(:format).to_h { |name, value| [name == :is_new ? "isNew" : name.to_s, value] }
          end
        end
      end
      if content["reply_to_user"]
        content["reply_to_user"] = content["reply_to_user"].transform_keys(&:to_s)
      end
      JSON.generate(content)
    end

    def self.decode(serialized)
      return if serialized.nil?
      data = JSON.parse(serialized)
      return { "unmapped_fields" => ["$format"] } unless data.is_a?(Hash)

      ALIASES.each do |source, target|
        next unless data.key?(source)
        data[target] ||= data[source]
        data.delete(source)
      end
      unmapped = data.keys - NATIVE_KEYS.values
      content = data.slice(*NATIVE_KEYS.values)
      %w[tags original_tags].each do |key|
        next if content[key].nil?
        tags = content[key]
        if !tags.is_a?(Array) || tags.size > MAX_TAGS || tags.any? { |tag| !tag.is_a?(String) && !tag.is_a?(Hash) }
          content.delete(key)
          unmapped << key
          next
        end
        content[key] = tags.map do |tag|
          if tag.is_a?(String)
            { "name" => tag, "format" => "NAME" }
          else
            unmapped.concat((tag.keys - TAG_KEYS).map { |name| "#{key}.#{name}" })
            tag.slice(*TAG_KEYS).merge("format" => "OBJECT")
          end
        end
      end
      if content["reply_to_user"].is_a?(Hash)
        unmapped.concat((content["reply_to_user"].keys - REPLY_USER_KEYS).map { |name| "reply_to_user.#{name}" })
        content["reply_to_user"] = content["reply_to_user"].slice(*REPLY_USER_KEYS)
      elsif content["reply_to_user"]
        content.delete("reply_to_user")
        unmapped << "reply_to_user"
      end
      unmapped = unmapped.uniq.sort
      unmapped = unmapped.first(MAX_UNMAPPED_FIELDS - 1) + ["$more"] if unmapped.size > MAX_UNMAPPED_FIELDS
      content.merge("unmapped_fields" => unmapped)
    rescue JSON::ParserError
      { "unmapped_fields" => ["$format"] }
    end
  end
end
