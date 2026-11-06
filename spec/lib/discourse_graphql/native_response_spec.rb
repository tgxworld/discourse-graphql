require "rails_helper"

RSpec.describe DiscourseGraphQL::NativeResponse do
  describe "#errors" do
    it "retains plural error precedence over a singular native error" do
      response = ActionDispatch::Response.new(422, {}, JSON.generate(errors: ["Plural message"], error: "Singular message"))
      expect(described_class.new(response).errors.map { |error| error.fetch(:message) }).to eq(["Plural message"])
      response = ActionDispatch::Response.new(422, {}, JSON.generate(errors: [], error: "Singular message"))
      expect(described_class.new(response).errors.map { |error| error.fetch(:message) }).to eq(["Singular message"])
    end

    it "retains generic failure messages for blank and unsupported singular errors" do
      [nil, false, 42, [], {}, "", "   "].each do |value|
        response = ActionDispatch::Response.new(422, {}, JSON.generate(error: value))
        expect(described_class.new(response).errors.map { |error| error.fetch(:message) }).to eq([I18n.t("discourse_graphql.errors.operation_failed")])
      end
    end
  end
end
