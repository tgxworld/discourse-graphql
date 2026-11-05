require "rails_helper"

RSpec.describe DiscourseGraphQL::RequestBodyLimit do
  describe "#call" do
    it "preserves Rack line iteration and rewind within the body bound" do
      application = lambda do |environment|
        input = environment.fetch("rack.input")
        expect(input.each.to_a).to eq(["one\n", "two\n"])
        input.rewind
        expect(input.read).to eq("one\ntwo\n")
        [200, {}, ["Read"]]
      end
      environment = Rack::MockRequest.env_for("/discourse-graphql/graphql", method: "POST", input: "one\ntwo\n")
      status, _headers, body = described_class.new(application).call(environment)
      expect(status).to eq(200)
      body.close
    end

    it "rejects declared oversized bodies before the application reads them" do
      app = described_class.new(->(_environment) { raise "Application must not run" })
      %w[/discourse-graphql/graphql /discourse-graphql/graphql.json /forum/discourse-graphql/graphql].each do |path|
        environment = Rack::MockRequest.env_for(path, method: "POST", input: "")
        environment["CONTENT_LENGTH"] = (described_class::MAX_DOCUMENT_BYTES + 1).to_s
        status, _headers, body = app.call(environment)
        expect(status).to eq(413)
        body.close if body.respond_to?(:close)
      end
    end

    it "retains overflow status when downstream code catches the read error" do
      stub_const(described_class, :MAX_DOCUMENT_BYTES, 16) do
        application = lambda do |environment|
          begin
            environment.fetch("rack.input").read
          rescue StandardError
            return [400, {}, ["Downstream error"]]
          end
          [200, {}, ["Unexpected success"]]
        end
        app = described_class.new(application)
        environment = Rack::MockRequest.env_for("/discourse-graphql/graphql.json", method: "POST", input: "x" * 32)
        environment.delete("CONTENT_LENGTH")
        status, _headers, body = app.call(environment)
        expect(status).to eq(413)
        expect(body.each.to_a.join).not_to include("Downstream error")
        body.close if body.respond_to?(:close)
      end
    end

    it "cleans files created before multipart parsing fails" do
      paths = []
      application = lambda do |environment|
        Rack::Multipart.parse_multipart(environment)
        [200, {}, ["Parsed"]]
      end
      raw = "--boundary\r\nContent-Disposition: form-data; name=\"0\"; filename=\"image.png\"\r\nContent-Type: image/png\r\n\r\npartial bytes without a closing boundary"
      environment = Rack::MockRequest.env_for("/discourse-graphql/graphql", method: "POST", input: raw, "CONTENT_TYPE" => "multipart/form-data; boundary=boundary")
      environment["rack.multipart.tempfile_factory"] = lambda do |_filename, _content_type|
        file = Tempfile.new("graphql-ingress-proof")
        paths << file.path
        file
      end
      status, _headers, body = described_class.new(application).call(environment)
      expect(status).to eq(400)
      body.close if body.respond_to?(:close)
      expect(paths).to be_present
      expect(paths.map { |path| File.exist?(path) }).to all(eq(false))
    end

    it "retains sources until response closure and then removes them" do
      paths = []
      application = lambda do |environment|
        Rack::Multipart.parse_multipart(environment)
        expect(paths.map { |path| File.exist?(path) }).to all(eq(true))
        [200, {}, ["Parsed"]]
      end
      raw = "--boundary\r\nContent-Disposition: form-data; name=\"0\"; filename=\"image.png\"\r\n\r\nbytes\r\n--boundary--\r\n"
      environment = Rack::MockRequest.env_for("/discourse-graphql/graphql", method: "POST", input: raw, "CONTENT_TYPE" => "multipart/form-data; boundary=boundary")
      environment["rack.multipart.tempfile_factory"] = lambda do |_filename, _content_type|
        file = Tempfile.new("graphql-ingress-proof")
        paths << file.path
        file
      end
      status, _headers, body = described_class.new(application).call(environment)
      expect(status).to eq(200)
      expect(paths).to be_present
      expect(paths.map { |path| File.exist?(path) }).to all(eq(true))
      body.close
      expect(paths.map { |path| File.exist?(path) }).to all(eq(false))
    end

    it "rejects duplicate multipart names and removes every parsed source" do
      paths = []
      application = ->(_environment) { raise "Ambiguous parts must not reach the application" }
      part = "--boundary\r\nContent-Disposition: form-data; name=\"0\"; filename=\"image.png\"\r\n\r\nbytes\r\n"
      environment = Rack::MockRequest.env_for("/discourse-graphql/graphql", method: "POST", input: part + part + "--boundary--\r\n", "CONTENT_TYPE" => "multipart/form-data; boundary=boundary")
      environment["rack.multipart.tempfile_factory"] = lambda do |_filename, _content_type|
        file = Tempfile.new("graphql-ingress-proof")
        paths << file.path
        file
      end
      status, _headers, body = described_class.new(application).call(environment)
      expect(status).to eq(400)
      expect(paths.size).to eq(2)
      expect(paths.map { |path| File.exist?(path) }).to all(eq(false))
      body.close if body.respond_to?(:close)
    end

    it "removes partial sources when streaming bodies exceed the limit" do
      paths = []
      raw = "--boundary\r\nContent-Disposition: form-data; name=\"unknown\"; filename=\"image.png\"\r\n\r\n" + "x" * 512 + "\r\n--boundary--\r\n"
      source = Class.new(StringIO) do
        def read(length = nil, buffer = nil)
          super([length || 32, 32].min, buffer)
        end
      end.new(raw)
      environment = Rack::MockRequest.env_for("/discourse-graphql/graphql", method: "POST", "CONTENT_TYPE" => "multipart/form-data; boundary=boundary")
      environment.delete("CONTENT_LENGTH")
      environment["rack.input"] = source
      environment["rack.multipart.tempfile_factory"] = lambda do |_filename, _content_type|
        file = Tempfile.new("graphql-ingress-proof")
        paths << file.path
        file
      end
      stub_const(described_class, :MAX_BODY_BYTES, 256) do
        app = described_class.new(->(_environment) { raise "Oversized body must not reach the application" })
        status, _headers, body = app.call(environment)
        expect(status).to eq(413)
        expect(paths).to be_present
        expect(paths.map { |path| File.exist?(path) }).to all(eq(false))
        body.close if body.respond_to?(:close)
      end
    end
  end
end
