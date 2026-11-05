require "rails_helper"
RSpec.describe UploadsController, type: :request do
  it "records completion at the exact native download threshold" do
    setup_s3
    SiteSetting.enable_direct_s3_uploads = true
    fake_s3 = FakeS3.create
    user = Fabricate(:user)
    key = Fabricate(:api_key, user: user)
    size = ExternalUploadManager::DOWNLOAD_LIMIT
    stub = Fabricate(:attachment_external_upload_stub, created_by: user, filesize: size)
    bucket = fake_s3.bucket(SiteSetting.s3_upload_bucket)
    bucket.put_object(key: stub.key, size: size, metadata: {}, last_modified: Time.current)
    logger = track_log_messages do
      post "/uploads/complete-external-upload.json", params: { unique_identifier: stub.unique_identifier }, headers: { "Api-Key" => key.key, "Api-Username" => user.username }
    end
    created_uploads = Upload.where(user_id: user.id).count
    puts JSON.generate(expected_size_bytes: size, native_completion_succeeded: response.status == 200, status: response.status, response: response.parsed_body, created_uploads: created_uploads, stub_exists: ExternalUploadStub.exists?(stub.id), temporary_object_exists: !!bucket.find_object(stub.key), errors: logger.errors.map { |error| error.lines.first(3).join })
    expect(response.status).to eq(422)
    expect(ExternalUploadStub.exists?(stub.id)).to eq(false)
    expect(bucket.find_object(stub.key)).to be_nil
    expect(created_uploads).to eq(0)
  end
end
