module DiscourseGraphQL
  module Types
    class CompleteUploadInput < BaseInputObject
      argument :unique_identifier, ID, required: true
      argument :pasted, Boolean, required: false
      argument :for_private_message, Boolean, required: false
      argument :for_site_setting, Boolean, required: false
      argument :site_setting_name, String, required: false
    end
  end
end
