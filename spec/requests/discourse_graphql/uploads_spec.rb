require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user) { Fabricate(:user, refresh_auto_groups: true) }
  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }
  let(:create_query) { 'mutation Upload($input: CreateUploadInput!) { createUpload(input: $input) { success upload { id url shortUrl originalFilename filesize width height } errors { code message retryAfterSeconds } } }' }

  describe "#execute" do
    it "uploads real multipart bytes and reuses the reference after a rejected reply" do
      events = DiscourseEvent.track_events(:before_upload_creation) { upload_image }
      expect(response.status).to eq(200)
      expect(response.parsed_body["errors"]).to be_blank
      result = response.parsed_body.dig("data", "createUpload")
      expect(result.fetch("success")).to eq(true)
      upload = Upload.find(result.dig("upload", "id"))
      expect(File.binread(Discourse.store.path_for(upload))).to eq(File.binread(file_from_fixtures("logo.png")))
      expect(result.dig("upload", "shortUrl")).to eq(upload.short_url)
      expect(events).to be_present
      expect(events.first.fetch(:params).first).to be_closed
      expect(events.first.fetch(:params).first.path).to be_nil

      topic = Fabricate(:topic)
      query = 'mutation Reply($input: CreatePostInput!) { createPost(input: $input) { status post { id cooked } errors { code } } }'
      post "/discourse-graphql/graphql", params: { query: query, variables: { input: { topicId: topic.id.to_s, raw: "a" } } }, headers: headers, as: :json
      expect(response.parsed_body.dig("data", "createPost", "status")).to eq("FAILED")
      expect(UploadReference.exists?(upload: upload, target_type: "Post")).to eq(false)

      raw = "A detailed reply with an image. ![image](#{upload.short_url})"
      expect do
        post "/discourse-graphql/graphql", params: { query: query, variables: { input: { topicId: topic.id.to_s, raw: raw } } }, headers: headers, as: :json
      end.not_to change(Upload, :count)
      expect(response.parsed_body.dig("data", "createPost", "status")).to eq("PUBLISHED")
      created_post = Post.find(response.parsed_body.dig("data", "createPost", "post", "id"))
      expect(created_post.cooked).to include(upload.url)
      expect(UploadReference.exists?(upload: upload, target: created_post)).to eq(true)
    end

    it "keeps a reused multipart source available across serial mutations" do
      query = 'mutation Upload($input: CreateUploadInput!) { first: createUpload(input: $input) { success upload { id } } second: createUpload(input: $input) { success upload { id } } }'
      upload_image(query: query)
      expect(response.parsed_body["errors"]).to be_blank
      first = response.parsed_body.dig("data", "first")
      second = response.parsed_body.dig("data", "second")
      expect(first.fetch("success")).to eq(true)
      expect(second.fetch("success")).to eq(true)
      expect(second.dig("upload", "id")).to eq(first.dig("upload", "id"))
      upload = Upload.find(first.dig("upload", "id"))
      expect(File.binread(Discourse.store.path_for(upload))).to eq(File.binread(file_from_fixtures("logo.png")))
    end

    it "shares native upload rate limits and keeps typed failure output" do
      RateLimiter.enable
      SiteSetting.max_uploads_per_minute = 1
      upload_image
      expect(response.parsed_body.dig("data", "createUpload", "success")).to eq(true)
      post "/uploads.json", params: { upload_type: "composer", file: Rack::Test::UploadedFile.new(file_from_fixtures("logo.png")) }, headers: headers
      expect(response.status).to eq(429)
      upload_image
      expect(response.parsed_body.dig("data", "createUpload", "success")).to eq(false)
      expect(response.parsed_body.dig("data", "createUpload", "errors", 0, "code")).to eq("RATE_LIMITED")
    end

    it "retains native avatar restrictions and file validation" do
      SiteSetting.discourse_connect_overrides_avatar = true
      upload_image(input: { uploadType: "avatar", file: nil })
      expect(response.parsed_body.dig("data", "createUpload", "success")).to eq(false)
      expect(response.parsed_body.dig("data", "createUpload", "upload")).to be_nil

      post "/discourse-graphql/graphql", params: multipart_parameters(file: Rack::Test::UploadedFile.new(file_from_fixtures("fake.jpg"))), headers: headers
      expect(response.parsed_body.dig("data", "createUpload", "success")).to eq(false)
      expect(response.parsed_body.dig("data", "createUpload", "errors")).to be_present
    end

    it "preserves native API only remote import" do
      url = "http://example.com/image.png"
      request = stub_request(:get, url).to_return(status: 200, body: File.binread(file_from_fixtures("logo.png")))
      parameters = { query: create_query, variables: { input: { uploadType: "composer", url: url } } }
      post "/discourse-graphql/graphql", params: parameters, headers: headers, as: :json
      expect(response.parsed_body.dig("data", "createUpload", "success")).to eq(true)
      expect(request).to have_been_requested.once
      sign_in(user)
      post "/discourse-graphql/graphql", params: parameters, as: :json
      expect(response.parsed_body.dig("data", "createUpload", "success")).to eq(false)
      expect(request).to have_been_requested.once
    end

    it "retains current permissions for metadata and short URL lookup" do
      owner = Fabricate(:user)
      private_post = Fabricate(:private_message_post, user: owner)
      upload = Fabricate(:secure_upload, user: owner, access_control_post: private_post, original_filename: "private-report.png")
      query = 'query Upload($url: String!, $shortUrls: [String!]!) { uploadMetadata(url: $url) { originalFilename width height humanFilesize } lookupUploadUrls(shortUrls: $shortUrls) { shortUrl url shortPath } currentUser { id } }'
      parameters = { query: query, variables: { url: upload.url, shortUrls: [upload.short_url] } }
      post "/discourse-graphql/graphql", params: parameters, headers: headers, as: :json
      expect(response.parsed_body.dig("data", "uploadMetadata")).to be_nil
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("FORBIDDEN")
      expect(response.parsed_body.dig("data", "lookupUploadUrls")).to eq([])
      expect(response.body).not_to include(upload.original_filename)
      expect(response.parsed_body.dig("data", "currentUser", "id")).to eq(user.id.to_s)

      key = Fabricate(:api_key, user: owner)
      post "/discourse-graphql/graphql", params: parameters, headers: { "Api-Key" => key.key, "Api-Username" => owner.username }, as: :json
      expect(response.parsed_body["errors"]).to be_blank
      expect(response.parsed_body.dig("data", "uploadMetadata", "originalFilename")).to eq(upload.original_filename)
      expect(response.parsed_body.dig("data", "lookupUploadUrls", 0, "shortUrl")).to eq(upload.short_url)
      private_post.topic.topic_allowed_users.where(user: owner).delete_all
      post "/discourse-graphql/graphql", params: parameters, headers: { "Api-Key" => key.key, "Api-Username" => owner.username }, as: :json
      expect(response.parsed_body.dig("data", "uploadMetadata")).to be_nil
      expect(response.parsed_body.dig("data", "lookupUploadUrls")).to eq([])
    end

    it "rejects malformed multipart maps before creating uploads" do
      variations = [
        { operations: [].to_json },
        { map: { "0" => ["variables.input.uploadType"] }.to_json },
        { map: { "0" => ["variables.missing.file"] }.to_json },
        { map: { "missing" => ["variables.input.file"] }.to_json },
        { map: { "0" => ["query"] }.to_json },
        { map: { "0" => ["variables.input.file", "variables.input.file"] }.to_json },
        { operations: "{" },
      ]
      variations.each do |override|
        expect do
          post "/discourse-graphql/graphql", params: multipart_parameters.merge(override), headers: headers
        end.not_to change(Upload, :count)
        expect(response.status).to eq(400)
      end
    end

    it "bounds query work and rejects forged upload values before persistence" do
      query = 'mutation Upload($input: CreateUploadInput!) { ' + 10.times.map { |index| "upload#{index}: createUpload(input: $input) { success }" }.join(" ") + ' }'
      expect { upload_image(query: query) }.not_to change(Upload, :count)
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("QUERY_TOO_COMPLEX")
      post "/discourse-graphql/graphql", params: { query: create_query, variables: { input: { uploadType: "composer", file: { tempfile: "/etc/passwd" } } } }, headers: headers, as: :json
      expect(response.parsed_body["errors"]).to be_present
      post "/discourse-graphql/graphql", params: { query: '{ lookupUploadUrls(shortUrls: [' + 101.times.map { '"upload://missing.png"' }.join(",") + ']) { url } }' }, headers: headers, as: :json
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
    end

    it "retains authentication, GET and readonly protections" do
      upload_image(request_headers: {})
      expect(response.parsed_body.dig("data", "createUpload", "errors", 0, "code")).to eq("UNAUTHENTICATED")
      get "/discourse-graphql/graphql", params: { query: 'mutation { createUpload(input: { uploadType: "composer", url: "http://example.com/image.png" }) { success } }' }, headers: headers
      expect(response.status).to eq(400)
      Discourse.enable_readonly_mode
      begin
        upload_image
        expect(response.status).to eq(503)
      ensure
        Discourse.disable_readonly_mode
      end
    end

    it "rejects browser CSRF and revoked credentials before native upload work" do
      sign_in(user)
      ActionController::Base.allow_forgery_protection = true
      begin
        expect { upload_image(request_headers: {}) }.not_to change(Upload, :count)
        expect(response.status).to eq(403)
        api_key.update!(revoked_at: Time.current)
        expect { upload_image }.not_to change(Upload, :count)
        expect(response.status).to eq(403)
      ensure
        ActionController::Base.allow_forgery_protection = false
      end
    end

    it "rejects raw body overflow and unknown file parts at the HTTP boundary" do
      stub_const(DiscourseGraphQL::RequestBodyLimit, :MAX_BODY_BYTES, 128) do
        expect { upload_image }.not_to change(Upload, :count)
        expect(response.status).to eq(413)
        expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("PAYLOAD_TOO_LARGE")
      end
      parameters = multipart_parameters.merge("unused" => Rack::Test::UploadedFile.new(file_from_fixtures("logo.png")))
      expect do
        post "/discourse-graphql/graphql.json", params: parameters, headers: headers
      end.not_to change(Upload, :count)
      expect(response.status).to eq(400)
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("BAD_REQUEST")
    end

    it "preserves native image transformations without consuming a reused source" do
      SiteSetting.authorized_extensions = "svg"
      user.update!(admin: true)
      svg = '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" onload="alert(1)"><rect width="10" height="10"/><script>alert(2)</script></svg>'
      file = Rack::Test::UploadedFile.new(StringIO.new(svg), "image/svg+xml", original_filename: "image.svg")
      query = 'mutation Upload($input: CreateUploadInput!) { first: createUpload(input: $input) { success upload { id } } second: createUpload(input: $input) { success upload { id } } }'
      post "/discourse-graphql/graphql", params: multipart_parameters(query: query, file: file), headers: headers
      expect(response.parsed_body["errors"]).to be_blank
      expect(response.parsed_body.dig("data", "first", "success")).to eq(true)
      expect(response.parsed_body.dig("data", "second", "success")).to eq(true)
      upload = Upload.find(response.parsed_body.dig("data", "second", "upload", "id"))
      stored = File.read(Discourse.store.path_for(upload))
      expect(stored).to include("rect")
      expect(stored).not_to include("onload", "script", "alert(")
    end

    it "forwards false and true options to native private attachment validation" do
      SiteSetting.authorized_extensions = "jpg"
      SiteSetting.allow_staff_to_upload_any_file_in_pm = true
      user.update!(moderator: true)
      file_path = Rails.root.join("LICENSE.txt")
      [false, true].each do |private_message|
        file = Rack::Test::UploadedFile.new(file_path)
        input = { uploadType: "composer", file: nil, forPrivateMessage: private_message }
        post "/discourse-graphql/graphql", params: multipart_parameters(input: input, file: file), headers: headers
        expect(response.parsed_body.dig("data", "createUpload", "success")).to eq(private_message)
      end
    end
  end

  private

  def multipart_parameters(query: create_query, input: { uploadType: "composer", file: nil }, file: nil)
    {
      operations: { query: query, variables: { input: input } }.to_json,
      map: { "0" => ["variables.input.file"] }.to_json,
      "0" => file || Rack::Test::UploadedFile.new(file_from_fixtures("logo.png")),
    }
  end

  def upload_image(query: create_query, input: { uploadType: "composer", file: nil }, request_headers: headers)
    post "/discourse-graphql/graphql", params: multipart_parameters(query: query, input: input), headers: request_headers
  end
end
