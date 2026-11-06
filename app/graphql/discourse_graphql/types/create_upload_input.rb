module DiscourseGraphQL
  module Types
    class CreateUploadInput < BaseInputObject
      argument :upload_type, String, required: true
      argument :file, UploadScalar, required: false
      argument :url, String, required: false
      argument :pasted, Boolean, required: false
      argument :for_private_message, Boolean, required: false
      argument :for_site_setting, Boolean, required: false
      argument :site_setting_name, String, required: false
      argument :retain_hours, Int, required: false
    end
  end
end
