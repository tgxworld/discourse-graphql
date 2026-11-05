require "rails_helper"
require "net/http"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user) { Fabricate(:user, refresh_auto_groups: true) }
  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }
  let(:bytes) { File.binread(file_from_fixtures("logo.png")) }
  let(:input) { { fileName: "logo.png", fileSizeBytes: bytes.bytesize, uploadType: "composer", sha1Checksum: Digest::SHA1.hexdigest(bytes) } }
  let(:start_query) { 'mutation Start($input: CreateExternalUploadInput!) { createDirectUpload(input: $input) { success ticket { uniqueIdentifier storageKey externalUploadIdentifier url signedHeaders { name value } } errors { code message } } }' }
  let(:complete_query) { 'mutation Complete($input: CompleteUploadInput!) { completeDirectUpload(input: $input) { success upload { id shortUrl filesize originalFilename } errors { code message } } }' }
  let(:multipart_query) { start_query.sub("createDirectUpload", "createMultipartUpload") }
  let(:parts_query) { 'mutation Parts($id: ID!, $parts: [Int!]!) { presignUploadParts(uniqueIdentifier: $id, partNumbers: $parts) { success parts { partNumber url } errors { code } } }' }
  let(:abort_query) { 'mutation Abort($id: ID!) { abortMultipartUpload(externalUploadIdentifier: $id) { success errors { code } } }' }

  describe "#execute" do
    before do
      setup_s3
      SiteSetting.enable_direct_s3_uploads = true
      SiteSetting.s3_backup_bucket = "s3-backup-bucket"
      SiteSetting.backup_location = BackupLocationSiteSetting::S3
      @fake_s3 = FakeS3.create
    end

    it "signs a direct PUT and promotes its real bytes through native completion" do
      result = graphql(query: start_query, variables: { input: input })
      expect(result["errors"]).to be_blank
      expect(response.headers.fetch("Cache-Control")).to match(/private|no-store/)
      ticket = result.dig("data", "createDirectUpload", "ticket")
      expect(ticket.fetch("url")).to include("Amz-Expires")
      signed_headers = ticket.fetch("signedHeaders").to_h { |header| [header.fetch("name"), header.fetch("value")] }
      expect(signed_headers).to include("x-amz-meta-sha1-checksum" => input.fetch(:sha1Checksum), "x-amz-acl" => "private")
      stub = ExternalUploadStub.find_by!(unique_identifier: ticket.fetch("uniqueIdentifier"))
      expect(stub).to have_attributes(created_by_id: user.id, filesize: bytes.bytesize, upload_type: "composer", multipart: false)

      stub_request(:put, ticket.fetch("url")).with(headers: signed_headers, body: bytes).to_return do
        seed_provider_object(ticket: ticket)
        { status: 200, body: "" }
      end
      uri = URI(ticket.fetch("url"))
      request = Net::HTTP::Put.new(uri.request_uri, signed_headers)
      request.body = bytes
      provider_response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |client| client.request(request) }
      expect(provider_response.code).to eq("200")
      stub_provider_download(ticket: ticket)

      result = graphql(query: complete_query, variables: { input: { uniqueIdentifier: ticket.fetch("uniqueIdentifier") } })
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "completeDirectUpload", "success")).to eq(true)
      upload = Upload.find(result.dig("data", "completeDirectUpload", "upload", "id"))
      expect(upload.sha1).to eq(Digest::SHA1.hexdigest(bytes))
      expect(upload.filesize).to eq(bytes.bytesize)
      expect(upload.user_id).to eq(user.id)
      expect(@fake_s3.bucket(SiteSetting.s3_upload_bucket).find_object(Discourse.store.get_path_for_upload(upload))).to be_present
      expect(@fake_s3.bucket(SiteSetting.s3_upload_bucket).find_object(ticket.fetch("storageKey"))).to be_nil
      expect(ExternalUploadStub.exists?(stub.id)).to eq(false)
      result = graphql(query: complete_query, variables: { input: { uniqueIdentifier: ticket.fetch("uniqueIdentifier") } })
      expect(result.dig("data", "completeDirectUpload", "errors", 0, "code")).to eq("NOT_FOUND")
    end

    it "retains ticket ownership for completion, part signing and abort" do
      ticket = graphql(query: multipart_query, variables: { input: input }).dig("data", "createMultipartUpload", "ticket")
      stub = ExternalUploadStub.find_by!(unique_identifier: ticket.fetch("uniqueIdentifier"))
      other = Fabricate(:user)
      key = Fabricate(:api_key, user: other)
      other_headers = { "Api-Key" => key.key, "Api-Username" => other.username }
      requests = [
        [complete_query, { input: { uniqueIdentifier: stub.unique_identifier } }, "completeDirectUpload"],
        [complete_query.sub("CompleteUploadInput", "CompleteMultipartUploadInput").sub("completeDirectUpload", "completeMultipartUpload"), { input: { uniqueIdentifier: stub.unique_identifier, parts: [{ partNumber: 1, etag: "part" }] } }, "completeMultipartUpload"],
        [parts_query, { id: stub.unique_identifier, parts: [1] }, "presignUploadParts"],
        [abort_query, { id: stub.external_upload_identifier }, "abortMultipartUpload"],
      ]
      provider_requests = @fake_s3.s3_client.api_requests.size
      requests.each do |query, variables, field|
        result = graphql(query: query, variables: variables, request_headers: other_headers)
        expect(result.dig("data", field, "success")).to eq(false)
        expect(result.dig("data", field, "errors", 0, "code")).to eq("NOT_FOUND")
        expect(ExternalUploadStub.exists?(stub.id)).to eq(true)
      end
      expect(@fake_s3.s3_client.api_requests.size).to eq(provider_requests)
    end

    it "creates, signs and completes native multipart uploads" do
      ticket = graphql(query: multipart_query, variables: { input: input }).dig("data", "createMultipartUpload", "ticket")
      expect(ticket.fetch("externalUploadIdentifier")).to be_present
      expect(ticket.fetch("url")).to be_nil
      @fake_s3.s3_client.stub_responses(:list_parts, { parts: [] })
      @fake_s3.s3_client.stub_responses(:complete_multipart_upload, {})
      result = graphql(query: parts_query, variables: { id: ticket.fetch("uniqueIdentifier"), parts: [2, 1] })
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "presignUploadParts", "success")).to eq(true)
      parts = result.dig("data", "presignUploadParts", "parts")
      expect(parts.map { |part| part.fetch("partNumber") }).to eq([2, 1])
      parts.each do |part|
        query = URI.decode_www_form(URI(part.fetch("url")).query).to_h
        expect(query).to include("partNumber" => part.fetch("partNumber").to_s, "uploadId" => ticket.fetch("externalUploadIdentifier"))
      end
      seed_provider_object(ticket: ticket)
      stub_provider_download(ticket: ticket)
      query = complete_query.sub("CompleteUploadInput", "CompleteMultipartUploadInput").sub("completeDirectUpload", "completeMultipartUpload")
      result = graphql(query: query, variables: { input: { uniqueIdentifier: ticket.fetch("uniqueIdentifier"), parts: [{ partNumber: 2, etag: "second" }, { partNumber: 1, etag: "first" }] } })
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "completeMultipartUpload", "success")).to eq(true)
      upload = Upload.find(result.dig("data", "completeMultipartUpload", "upload", "id"))
      expect(upload.sha1).to eq(Digest::SHA1.hexdigest(bytes))
      provider_completion = @fake_s3.s3_client.api_requests.find { |request| request.fetch(:operation_name) == :complete_multipart_upload }
      expect(provider_completion.dig(:params, :multipart_upload, :parts)).to eq([{ part_number: 1, etag: "first" }, { part_number: 2, etag: "second" }])
      expect(ExternalUploadStub.exists?(unique_identifier: ticket.fetch("uniqueIdentifier"))).to eq(false)
    end

    it "retains native abort and unknown identifier acknowledgement" do
      ticket = graphql(query: multipart_query, variables: { input: input }).dig("data", "createMultipartUpload", "ticket")
      @fake_s3.s3_client.stub_responses(:abort_multipart_upload, {})
      result = graphql(query: abort_query, variables: { id: ticket.fetch("externalUploadIdentifier") })
      expect(result.dig("data", "abortMultipartUpload", "success")).to eq(true)
      expect(ExternalUploadStub.exists?(unique_identifier: ticket.fetch("uniqueIdentifier"))).to eq(false)
      result = graphql(query: abort_query, variables: { id: ticket.fetch("externalUploadIdentifier") })
      expect(result.dig("data", "abortMultipartUpload", "success")).to eq(true)
    end

    it "preserves size mismatch cleanup and the native temporary upload ban" do
      ticket = graphql(query: start_query, variables: { input: input }).dig("data", "createDirectUpload", "ticket")
      seed_provider_object(ticket: ticket, size: bytes.bytesize + 1)
      result = graphql(query: complete_query, variables: { input: { uniqueIdentifier: ticket.fetch("uniqueIdentifier") } })
      expect(result.dig("data", "completeDirectUpload", "success")).to eq(false)
      expect(result.dig("data", "completeDirectUpload", "upload")).to be_nil
      expect(ExternalUploadManager.user_banned?(user)).to eq(true)
      expect(ExternalUploadStub.exists?(unique_identifier: ticket.fetch("uniqueIdentifier"))).to eq(false)
      expect(@fake_s3.bucket(SiteSetting.s3_upload_bucket).find_object(ticket.fetch("storageKey"))).to be_nil
      expect do
        result = graphql(query: start_query, variables: { input: input })
        expect(result.dig("data", "createDirectUpload", "errors", 0, "code")).to eq("FORBIDDEN")
      end.not_to change(ExternalUploadStub, :count)
    end

    it "retains checksum failure and debug state without exposing diagnostics" do
      ticket = graphql(query: start_query, variables: { input: input }).dig("data", "createDirectUpload", "ticket")
      seed_provider_object(ticket: ticket, checksum: "mismatched-checksum")
      stub_provider_download(ticket: ticket)
      SiteSetting.enable_upload_debug_mode = true
      result = graphql(query: complete_query, variables: { input: { uniqueIdentifier: ticket.fetch("uniqueIdentifier") } })
      expect(result.dig("data", "completeDirectUpload", "success")).to eq(false)
      expect(result.dig("data", "completeDirectUpload", "upload")).to be_nil
      expect(ExternalUploadStub.find_by!(unique_identifier: ticket.fetch("uniqueIdentifier")).status).to eq(ExternalUploadStub.statuses[:failed])
      expect(response.body).not_to include("ChecksumMismatchError", "external_upload_manager.rb")
    end

    it "keeps native backup access restrictions and completion without an Upload row" do
      backup_input = input.merge(fileName: "backup.tar.gz", uploadType: "backup", sha1Checksum: nil)
      result = graphql(query: start_query, variables: { input: backup_input })
      expect(result.dig("data", "createDirectUpload", "errors", 0, "code")).to eq("FORBIDDEN")
      user.update!(admin: true)
      ticket = graphql(query: multipart_query, variables: { input: backup_input }).dig("data", "createMultipartUpload", "ticket")
      @fake_s3.s3_client.stub_responses(:list_parts, { parts: [] })
      @fake_s3.s3_client.stub_responses(:complete_multipart_upload, {})
      @fake_s3.bucket(SiteSetting.s3_backup_bucket).put_object(key: ticket.fetch("storageKey"), size: bytes.bytesize, metadata: {}, last_modified: Time.current)
      query = complete_query.sub("CompleteUploadInput", "CompleteMultipartUploadInput").sub("completeDirectUpload", "completeMultipartUpload")
      user.update!(admin: false)
      result = graphql(query: query, variables: { input: { uniqueIdentifier: ticket.fetch("uniqueIdentifier"), parts: [{ partNumber: 1, etag: "backup" }] } })
      expect(result.dig("data", "completeMultipartUpload", "errors", 0, "code")).to eq("FORBIDDEN")
      expect(ExternalUploadStub.exists?(unique_identifier: ticket.fetch("uniqueIdentifier"))).to eq(true)
      user.update!(admin: true)
      expect do
        result = graphql(query: query, variables: { input: { uniqueIdentifier: ticket.fetch("uniqueIdentifier"), parts: [{ partNumber: 1, etag: "backup" }] } })
        expect(result.dig("data", "completeMultipartUpload", "success")).to eq(true)
        expect(result.dig("data", "completeMultipartUpload", "upload")).to be_nil
      end.not_to change(Upload, :count)
      expect(ExternalUploadStub.exists?(unique_identifier: ticket.fetch("uniqueIdentifier"))).to eq(false)
      backup_bucket = @fake_s3.bucket(SiteSetting.s3_backup_bucket)
      expect(backup_bucket.find_object("#{RailsMultisite::ConnectionManagement.current_db}/backup.tar.gz")).to be_present
      expect(backup_bucket.find_object(ticket.fetch("storageKey"))).to be_nil
    end

    it "shares native creation allowance with the existing HTTP endpoint" do
      RateLimiter.enable
      SiteSetting.max_presigned_put_per_minute = 1
      result = graphql(query: start_query, variables: { input: input })
      expect(result.dig("data", "createDirectUpload", "success")).to eq(true)
      post "/uploads/generate-presigned-put.json", params: { file_name: "logo.png", file_size: bytes.bytesize, type: "composer" }, headers: headers
      expect(response.status).to eq(429)
      result = graphql(query: start_query, variables: { input: input })
      expect(result.dig("data", "createDirectUpload", "errors", 0, "code")).to eq("RATE_LIMITED")
    end

    it "retains native local and disabled storage responses" do
      SiteSetting.enable_direct_s3_uploads = false
      result = graphql(query: start_query, variables: { input: input })
      expect(result.dig("data", "createDirectUpload", "errors", 0, "code")).to eq("NOT_FOUND")
      SiteSetting.enable_direct_s3_uploads = true
      SiteSetting.enable_s3_uploads = false
      result = graphql(query: start_query, variables: { input: input })
      expect(result.dig("data", "createDirectUpload", "errors", 0, "code")).to eq("NOT_FOUND")
    end

    it "rejects invalid typed bounds and excessive work before creating tickets" do
      [0, -1, 2**63].each do |size|
        expect do
          result = graphql(query: start_query, variables: { input: input.merge(fileSizeBytes: size.to_s) })
          expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
        end.not_to change(ExternalUploadStub, :count)
      end
      query = 'mutation Many($input: CreateExternalUploadInput!) { ' + 10.times.map { |index| "upload#{index}: createDirectUpload(input: $input) { success }" }.join(" ") + ' }'
      expect do
        result = graphql(query: query, variables: { input: input })
        expect(result.dig("errors", 0, "extensions", "code")).to eq("QUERY_TOO_COMPLEX")
      end.not_to change(ExternalUploadStub, :count)
      [[0], [10001], [1, 1], (1..101).to_a].each do |parts|
        result = graphql(query: parts_query, variables: { id: SecureRandom.uuid, parts: parts })
        expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      end
      query = complete_query.sub("CompleteUploadInput", "CompleteMultipartUploadInput").sub("completeDirectUpload", "completeMultipartUpload")
      [[], [{ partNumber: 0, etag: "part" }], [{ partNumber: 1, etag: " " }], [{ partNumber: 1, etag: "x" * 2049 }], [{ partNumber: 1, etag: "one" }, { partNumber: 1, etag: "two" }]].each do |parts|
        result = graphql(query: query, variables: { input: { uniqueIdentifier: SecureRandom.uuid, parts: parts } })
        expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      end
    end

    it "admits the native 10000 part completion within body and query bounds" do
      ticket = graphql(query: multipart_query, variables: { input: input }).dig("data", "createMultipartUpload", "ticket")
      @fake_s3.s3_client.stub_responses(:list_parts, { parts: [] })
      @fake_s3.s3_client.stub_responses(:complete_multipart_upload, {})
      seed_provider_object(ticket: ticket)
      stub_provider_download(ticket: ticket)
      query = complete_query.sub("CompleteUploadInput", "CompleteMultipartUploadInput").sub("completeDirectUpload", "completeMultipartUpload")
      parts = (1..10000).map { |number| { partNumber: number, etag: "etag#{number}" } }
      result = graphql(query: query, variables: { input: { uniqueIdentifier: ticket.fetch("uniqueIdentifier"), parts: parts } })
      expect(response.status).to eq(200)
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "completeMultipartUpload", "success")).to eq(true)
      provider_completion = @fake_s3.s3_client.api_requests.find { |request| request.fetch(:operation_name) == :complete_multipart_upload }
      expect(provider_completion.dig(:params, :multipart_upload, :parts).size).to eq(10000)
    end

    it "retains authentication, GET and readonly boundaries" do
      result = graphql(query: start_query, variables: { input: input }, request_headers: {})
      expect(result.dig("data", "createDirectUpload", "errors", 0, "code")).to eq("UNAUTHENTICATED")
      get "/discourse-graphql/graphql", params: { query: start_query, variables: { input: input }.to_json }, headers: headers
      expect(response.status).to eq(400)
      Discourse.enable_readonly_mode
      begin
        graphql(query: start_query, variables: { input: input })
        expect(response.status).to eq(503)
      ensure
        Discourse.disable_readonly_mode
      end
    end

    it "preserves native large file promotion without downloading the bytes" do
      size = 200 * 1024 * 1024
      SiteSetting.authorized_extensions = "pdf"
      SiteSetting.max_attachment_size_kb = 500 * 1024
      ticket = graphql(query: start_query, variables: { input: input.merge(fileName: "large.pdf", fileSizeBytes: size, sha1Checksum: nil) }).dig("data", "createDirectUpload", "ticket")
      seed_provider_object(ticket: ticket, size: size)
      result = graphql(query: complete_query, variables: { input: { uniqueIdentifier: ticket.fetch("uniqueIdentifier") } })
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "completeDirectUpload", "success")).to eq(true)
      expect(result.dig("data", "completeDirectUpload", "upload", "filesize")).to eq(size.to_s)
      upload = Upload.find(result.dig("data", "completeDirectUpload", "upload", "id"))
      expect(upload.filesize).to eq(size)
      expect(@fake_s3.bucket(SiteSetting.s3_upload_bucket).find_object(Discourse.store.get_path_for_upload(upload))).to be_present
    end

    it "preserves false and true native private upload options" do
      SiteSetting.secure_uploads = true
      [false, true].each do |private_message|
        ticket = graphql(query: start_query, variables: { input: input.merge(uploadType: "attachment") }).dig("data", "createDirectUpload", "ticket")
        seed_provider_object(ticket: ticket)
        stub_provider_download(ticket: ticket)
        result = graphql(query: complete_query, variables: { input: { uniqueIdentifier: ticket.fetch("uniqueIdentifier"), forPrivateMessage: private_message, forSiteSetting: false } })
        expect(result.dig("data", "completeDirectUpload", "success")).to eq(true)
        upload = Upload.find(result.dig("data", "completeDirectUpload", "upload", "id"))
        expect(upload.secure).to eq(private_message)
      end
    end

    it "signs the final 100 native part numbers without truncating or omitting URLs" do
      ticket = graphql(query: multipart_query, variables: { input: input }).dig("data", "createMultipartUpload", "ticket")
      @fake_s3.s3_client.stub_responses(:list_parts, { parts: [] })
      numbers = (9901..10000).to_a
      result = graphql(query: parts_query, variables: { id: ticket.fetch("uniqueIdentifier"), parts: numbers })
      expect(result["errors"]).to be_blank
      parts = result.dig("data", "presignUploadParts", "parts")
      expect(parts.map { |part| part.fetch("partNumber") }).to eq(numbers)
      parts.each do |part|
        expect(URI.decode_www_form(URI(part.fetch("url")).query).to_h).to include("partNumber" => part.fetch("partNumber").to_s)
      end
    end

    it "retains native file size rejection and shared part signing allowance" do
      result = graphql(query: start_query, variables: { input: input.merge(fileName: "oversize.pdf", fileSizeBytes: 20 * 1024 * 1024) })
      expect(result.dig("data", "createDirectUpload", "success")).to eq(false)
      expect(result.dig("data", "createDirectUpload", "errors", 0, "code")).to eq("BAD_USER_INPUT")
      RateLimiter.enable
      SiteSetting.max_batch_presign_multipart_per_minute = 1
      ticket = graphql(query: multipart_query, variables: { input: input }).dig("data", "createMultipartUpload", "ticket")
      @fake_s3.s3_client.stub_responses(:list_parts, { parts: [] })
      result = graphql(query: parts_query, variables: { id: ticket.fetch("uniqueIdentifier"), parts: [1] })
      expect(result.dig("data", "presignUploadParts", "success")).to eq(true)
      post "/uploads/batch-presign-multipart-parts.json", params: { unique_identifier: ticket.fetch("uniqueIdentifier"), part_numbers: [1] }, headers: headers
      expect(response.status).to eq(429)
      result = graphql(query: parts_query, variables: { id: ticket.fetch("uniqueIdentifier"), parts: [1] })
      expect(result.dig("data", "presignUploadParts", "errors", 0, "code")).to eq("RATE_LIMITED")
    end

    it "protects every native action from anonymous callers and retains browser CSRF" do
      requests = [
        [start_query, { input: input }, "createDirectUpload"],
        [multipart_query, { input: input }, "createMultipartUpload"],
        [complete_query, { input: { uniqueIdentifier: SecureRandom.uuid } }, "completeDirectUpload"],
        [complete_query.sub("CompleteUploadInput", "CompleteMultipartUploadInput").sub("completeDirectUpload", "completeMultipartUpload"), { input: { uniqueIdentifier: SecureRandom.uuid, parts: [{ partNumber: 1, etag: "part" }] } }, "completeMultipartUpload"],
        [parts_query, { id: SecureRandom.uuid, parts: [1] }, "presignUploadParts"],
        [abort_query, { id: "unknown-provider-id" }, "abortMultipartUpload"],
      ]
      requests.each do |query, variables, field|
        result = graphql(query: query, variables: variables, request_headers: {})
        expect(result.dig("data", field, "errors", 0, "code")).to eq("UNAUTHENTICATED")
      end
      sign_in(user)
      ActionController::Base.allow_forgery_protection = true
      begin
        expect { graphql(query: start_query, variables: { input: input }, request_headers: {}) }.not_to change(ExternalUploadStub, :count)
        expect(response.status).to eq(403)
      ensure
        ActionController::Base.allow_forgery_protection = false
      end
    end
  end

  private

  def graphql(query:, variables:, request_headers: headers)
    post "/discourse-graphql/graphql", params: { query: query, variables: variables }, headers: request_headers, as: :json
    response.parsed_body
  end

  def seed_provider_object(ticket:, size: bytes.bytesize, checksum: Digest::SHA1.hexdigest(bytes))
    @fake_s3.bucket(SiteSetting.s3_upload_bucket).put_object(key: ticket.fetch("storageKey"), size: size, metadata: { "sha1-checksum" => checksum }, last_modified: Time.current)
  end

  def stub_provider_download(ticket:)
    url = Discourse.store.signed_url_for_path(ticket.fetch("storageKey"), include_content_disposition: false)
    uri = URI(url)
    stub_request(:get, "#{uri.scheme}://#{uri.host}#{uri.path}").with(query: hash_including({})).to_return(status: 200, body: bytes)
  end
end
