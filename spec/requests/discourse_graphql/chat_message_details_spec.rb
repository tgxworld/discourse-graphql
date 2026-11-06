require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user) { Fabricate(:user, refresh_auto_groups: true) }
  fab!(:author, :user)
  fab!(:channel, :category_channel)
  fab!(:message) { Fabricate(:chat_message, chat_channel: channel, user: author) }

  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }

  before do
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    channel.add(user)
  end

  describe "#execute" do
    it "reads native bookmark, flag, revision and pin presentation without rebuilding resources" do
      SiteSetting.chat_pinned_messages = true
      bookmark =
        Fabricate(
          :bookmark,
          user: user,
          bookmarkable: message,
          name: "Own reminder",
          reminder_at: 1.hour.from_now,
        )
      Fabricate(:chat_message_revision, chat_message: message)
      Fabricate(:chat_pinned_message, chat_message: message, user: user)
      native = native_message

      result =
        details(
          selection:
            "nodes { id edited pinned isAction threadTitle availableFlags bookmark { id name reminderAt autoDeletePreference targetId targetType } }",
        )

      expect(result["errors"]).to be_blank
      node = result.dig("data", "chatMessages", "nodes", 0)
      expect(node).to include(
        "id" => message.id.to_s,
        "edited" => native.fetch("edited"),
        "pinned" => native.fetch("pinned"),
        "isAction" => native.fetch("is_action"),
        "threadTitle" => native["thread_title"],
        "availableFlags" => native.fetch("available_flags"),
      )
      expect(node.fetch("bookmark")).to include(
        "id" => bookmark.id.to_s,
        "name" => native.dig("bookmark", "name"),
        "targetId" => message.id.to_s,
        "targetType" => native.dig("bookmark", "bookmarkable_type"),
      )
      expect(Time.iso8601(node.dig("bookmark", "reminderAt")).to_r).to eq(
        Time.iso8601(native.dig("bookmark", "reminder_at")).to_r,
      )
    end

    it "preserves false booleans, empty flags and native omission" do
      SiteSetting.chat_pinned_messages = false
      SiteSetting.chat_message_flag_allowed_groups = ""
      native = native_message

      result = details(selection: "nodes { edited pinned isAction availableFlags bookmark { id } }")

      expect(result["errors"]).to be_blank
      expect(result.dig("data", "chatMessages", "nodes", 0)).to eq(
        "edited" => nil,
        "pinned" => nil,
        "isAction" => native.fetch("is_action"),
        "availableFlags" => native.fetch("available_flags"),
        "bookmark" => nil,
      )
    end

    it "keeps message bookmarks scoped to the native actor" do
      own = Fabricate(:bookmark, user: user, bookmarkable: message, name: "First actor")
      other = Fabricate(:user, refresh_auto_groups: true)
      other_bookmark =
        Fabricate(:bookmark, user: other, bookmarkable: message, name: "Second actor")
      other_key = Fabricate(:api_key, user: other)
      selection = "nodes { bookmark { id name } }"
      expect(
        details(selection: selection).dig("data", "chatMessages", "nodes", 0, "bookmark"),
      ).to eq("id" => own.id.to_s, "name" => own.name)

      result =
        details(
          selection: selection,
          request_headers: {
            "Api-Key" => other_key.key,
            "Api-Username" => other.username,
          },
        )

      expect(result["errors"]).to be_blank
      expect(result.dig("data", "chatMessages", "nodes", 0, "bookmark")).to eq(
        "id" => other_bookmark.id.to_s,
        "name" => other_bookmark.name,
      )
    end

    it "retains native reply preview and webhook presentation without provider secrets" do
      hook =
        Fabricate(
          :incoming_chat_webhook,
          chat_channel: channel,
          username: "Native hook",
          emoji: ":wave:",
        )
      Fabricate(:chat_webhook_event, chat_message: message, incoming_chat_webhook: hook)
      reply = Fabricate(:chat_message, chat_channel: channel, user: author, in_reply_to: message)
      native = native_message

      result =
        details(
          selection:
            "nodes { inReplyTo { id cooked excerpt user { id username } webhook { username emoji } } webhook { username emoji } }",
        )

      expect(result["errors"]).to be_blank
      node = result.dig("data", "chatMessages", "nodes", 0)
      expect(node["webhook"]).to eq(native["chat_webhook_event"])
      expect(node.fetch("inReplyTo")).to include(
        "id" => message.id.to_s,
        "cooked" => native.dig("in_reply_to", "cooked"),
        "excerpt" => native.dig("in_reply_to", "excerpt"),
        "webhook" => native.dig("in_reply_to", "chat_webhook_event"),
      )
      expect(node.dig("inReplyTo", "user", "username")).to eq(
        native.dig("in_reply_to", "user", "username"),
      )
      expect(result.to_s).not_to include(hook.key, hook.url)
      expect(reply.in_reply_to_id).to eq(message.id)
    end

    it "reads attachment fields without restricting child output to parent field names" do
      SiteSetting.authorized_extensions += "|mp4"
      upload = Fabricate(:upload)
      image =
        Fabricate(
          :optimized_image,
          upload: upload,
          width: upload.thumbnail_width,
          height: upload.thumbnail_height,
        )
      video = Fabricate(:optimized_video, upload: upload)
      message.uploads = [upload]
      native = native_message.fetch("uploads").first

      result =
        details(
          selection:
            "nodes { uploads(first: 1) { nodes { id originalFilename url filesize thumbnail { id uploadId width height url } optimizedVideo { id uploadId url originalFilename extension filesize sha1 } } totalCount } }",
        )

      expect(result["errors"]).to be_blank
      value = result.dig("data", "chatMessages", "nodes", 0, "uploads", "nodes", 0)
      expect(value).to include(
        "id" => upload.id.to_s,
        "originalFilename" => native.fetch("original_filename"),
        "url" => native.fetch("url"),
        "filesize" => native.fetch("filesize").to_s,
      )
      if native["thumbnail"]
        expect(value["thumbnail"]).to include(
          "id" => image.id.to_s,
          "width" => native.dig("thumbnail", "width"),
          "url" => native.dig("thumbnail", "url"),
        )
      else
        expect(value["thumbnail"]).to be_nil
      end
      if native["optimized_video"]
        expect(value["optimizedVideo"]).to include(
          "id" => video.id.to_s,
          "url" => native.dig("optimized_video", "url"),
          "originalFilename" => native.dig("optimized_video", "original_filename"),
        )
      else
        expect(value["optimizedVideo"]).to be_nil
      end
    end

    it "retains native secure attachment URL output after private channel authorization" do
      setup_s3
      SiteSetting.secure_uploads = true
      group = Fabricate(:group, users: [user])
      restricted = Fabricate(:private_category_channel, group: group)
      upload = Fabricate(:secure_upload_s3)
      entry = Fabricate(:chat_message, chat_channel: restricted, uploads: [upload])
      native = native_message(channel_id: restricted.id).fetch("uploads").first

      result =
        details(
          channel_id: restricted.id,
          selection: "nodes { uploads(first: 1) { nodes { id url } } }",
        )

      expect(result["errors"]).to be_blank
      expect(result.dig("data", "chatMessages", "nodes", 0, "uploads", "nodes", 0)).to eq(
        "id" => upload.id.to_s,
        "url" => native.fetch("url"),
      )
      expect(native.fetch("url")).not_to eq(upload.url)
      group.remove(user)
      result =
        details(
          channel_id: restricted.id,
          selection: "nodes { uploads(first: 1) { nodes { url } } }",
        )
      expect(result.dig("data", "chatMessages")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("FORBIDDEN")
      expect(result.to_s).not_to include(entry.message, upload.url)
    end

    it "pages only retained native mention samples in their native order" do
      SiteSetting.max_mentions_per_chat_message = 2
      mentioned = Fabricate.times(3, :user)
      mentioned.reverse_each do |actor|
        Fabricate(:user_chat_mention, chat_message: message, user: actor)
      end
      native = native_message.fetch("mentioned_users")
      first =
        details(
          selection:
            "nodes { mentionedUsers(first: 1) { nodes { id username } totalCount pageInfo { endCursor hasNextPage } } }",
        )
      expect(first["errors"]).to be_blank
      page = first.dig("data", "chatMessages", "nodes", 0, "mentionedUsers")
      cursor = page.dig("pageInfo", "endCursor")
      expect(cursor).to be_present
      expect(page.fetch("totalCount")).to eq("2")

      result =
        details(
          selection:
            "nodes { mentionedUsers(first: 1, after: #{cursor.to_json}) { nodes { id username } totalCount pageInfo { endCursor hasNextPage } } }",
        )

      expect(result["errors"]).to be_blank
      next_page = result.dig("data", "chatMessages", "nodes", 0, "mentionedUsers")
      expect([page, next_page].flat_map { |value| value.fetch("nodes") }).to eq(
        native.map { |row| { "id" => row.fetch("id").to_s, "username" => row.fetch("username") } },
      )
      expect(next_page.dig("pageInfo", "hasNextPage")).to eq(false)
    end

    it "retains native author role, flair and status privacy" do
      SiteSetting.enable_user_status = true
      flair = Fabricate(:group, flair_bg_color: "ffffff", flair_color: "000000", flair_icon: "star")
      author.update!(admin: true, flair_group: flair, primary_group: flair)
      author.set_status!("Native status", "heart")
      native = native_message.fetch("user")
      selection =
        "nodes { author { id username admin moderator staff newUser primaryGroupName flairName flairUrl flairBgColor flairColor flairGroupId status { description emoji endsAt messageBusLastId } } }"
      result = details(selection: selection)
      expect(result["errors"]).to be_blank
      value = result.dig("data", "chatMessages", "nodes", 0, "author")
      expect(value).to include(
        "admin" => native.fetch("admin"),
        "moderator" => native.fetch("moderator"),
        "staff" => native.fetch("staff"),
        "newUser" => native.fetch("new_user"),
        "primaryGroupName" => native["primary_group_name"],
        "flairName" => native["flair_name"],
        "flairGroupId" => native["flair_group_id"]&.to_s,
      )
      expect(value.dig("status", "description")).to eq(native.dig("status", "description"))
      author.user_option.update!(hide_profile: true)

      result = details(selection: selection)

      expect(result["errors"]).to be_blank
      expect(result.dig("data", "chatMessages", "nodes", 0, "author", "status")).to be_nil
    end

    it "retains typed native blocks and excludes private button values" do
      secret = "Private interaction payload"
      message.update!(
        blocks: [
          {
            type: "confirmation",
            title: "**Confirm**",
            question: "Change this?",
            status: "Pending",
            error: "Native error",
            description_label: "Details",
            show_description: false,
            parameters: [{ label: "Name", value: "New value", color: "ff0000" }],
            changes: [
              {
                label: "Name",
                before: "Old",
                after: "New",
                before_color: "000000",
                after_color: "ffffff",
              },
            ],
            elements: [
              {
                type: "button",
                value: secret,
                text: {
                  type: "plain_text",
                  text: "Confirm",
                },
                style: "primary",
                icon: "check",
              },
            ],
          },
          {
            type: "informative",
            elements: [
              {
                type: "category",
                title: "Native category",
                color: "ff0000",
                url: "/c/native",
                description: "Native description",
                parent_name: "Parent",
                parent_color: "000000",
              },
            ],
          },
        ],
      )
      native = native_message.fetch("blocks")
      result = details(selection: <<~GRAPHQL)
        nodes { blocks(first: 5) { totalCount nodes {
          type title cookedTitle cookedQuestion cookedStatus cookedError showDescription descriptionLabel
          parameters(first: 1) { nodes { label value color } }
          changes(first: 1) { nodes { label before after beforeColor afterColor } }
          elements(first: 10) { nodes {
            __typename
            ... on ChatButtonElement { type actionId style icon text { type text } }
            ... on ChatCategoryElement { type title color description url parentName parentColor }
          } }
        } } }
      GRAPHQL
      expect(result["errors"]).to be_blank
      blocks = result.dig("data", "chatMessages", "nodes", 0, "blocks", "nodes")
      expect(blocks.first).to include(
        "type" => "confirmation",
        "title" => native.first.fetch("title"),
        "cookedTitle" => native.first.fetch("cooked_title"),
        "cookedQuestion" => native.first.fetch("cooked_question"),
        "cookedStatus" => native.first.fetch("cooked_status"),
        "cookedError" => native.first.fetch("cooked_error"),
        "showDescription" => false,
      )
      expect(blocks.first.dig("parameters", "nodes")).to eq(native.first.fetch("parameters"))
      expect(blocks.first.dig("elements", "nodes", 0)).to include(
        "__typename" => "ChatButtonElement",
        "actionId" => native.first.dig("elements", 0, "action_id"),
        "text" => native.first.dig("elements", 0, "text"),
      )
      expect(blocks.last.dig("elements", "nodes", 0)).to include(
        "__typename" => "ChatCategoryElement",
        "title" => native.last.dig("elements", 0, "title"),
        "parentName" => native.last.dig("elements", 0, "parent_name"),
      )
      expect(result.to_s).not_to include(secret)
    end

    it "binds attachment cursors to the parent even when native collections are identical" do
      uploads = Fabricate.times(2, :upload)
      message.uploads = uploads
      selection = "nodes { uploads(first: 1) { nodes { id } pageInfo { endCursor } } }"
      first = details(selection: selection)
      cursor = first.dig("data", "chatMessages", "nodes", 0, "uploads", "pageInfo", "endCursor")
      expect(cursor).to be_present
      first_native = native_message.fetch("uploads")
      Fabricate(:chat_message, chat_channel: channel, uploads: uploads)
      expect(native_message.fetch("uploads")).to eq(first_native)

      result =
        details(selection: "nodes { uploads(first: 1, after: #{cursor.to_json}) { nodes { id } } }")

      expect(result.dig("data", "chatMessages", "nodes", 0, "uploads")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
    end

    it "reports unavailable cursor delivery when native parent identity is withheld" do
      message.uploads = Fabricate.times(2, :upload)
      cursor =
        details(selection: "nodes { uploads(first: 1) { pageInfo { endCursor } } }").dig(
          "data",
          "chatMessages",
          "nodes",
          0,
          "uploads",
          "pageInfo",
          "endCursor",
        )
      expect(cursor).to be_present
      restricted =
        Class.new(Chat::MessageSerializer) do
          def include_id?
            false
          end
        end
      stub_const(Chat, :MessageSerializer, restricted) do
        result =
          details(selection: "nodes { uploads(first: 1) { nodes { id } pageInfo { endCursor } } }")
        expect(result.dig("data", "chatMessages", "nodes", 0, "uploads")).to be_nil
        expect(result.dig("errors", 0, "extensions", "code")).to eq("UNAVAILABLE")
        result = details(selection: "nodes { uploads(first: 1) { nodes { id } } }")
        expect(result["errors"]).to be_blank
        expect(result.dig("data", "chatMessages", "nodes", 0, "uploads", "nodes").size).to eq(1)
        result =
          details(
            selection: "nodes { uploads(first: 1, after: #{cursor.to_json}) { nodes { id } } }",
          )
        expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      end
    end

    it "retains native collection suppression and filtered empty pagination" do
      Fabricate(:chat_message, chat_channel: channel)
      filtered =
        Class.new(Chat::MessagesSerializer) do
          def messages
            []
          end
        end
      stub_const(Chat, :MessagesSerializer, filtered) do
        result = details(selection: "nodes { id } pageInfo { startCursor hasPreviousPage }")
        expect(result["errors"]).to be_blank
        expect(result.dig("data", "chatMessages")).to eq("nodes" => [], "pageInfo" => nil)
      end
      omitted =
        Class.new(Chat::MessagesSerializer) do
          def include_messages?
            false
          end
        end
      stub_const(Chat, :MessagesSerializer, omitted) do
        result = details(selection: "nodes { id } pageInfo { startCursor }")
        expect(result["errors"]).to be_blank
        expect(result.dig("data", "chatMessages")).to eq("nodes" => nil, "pageInfo" => nil)
      end
    end

    it "retains native message serializer instance overrides in channel history" do
      decorated =
        Class.new(Chat::MessagesSerializer) do
          def messages
            super.each { |row| row.define_singleton_method(:excerpt) { "Native #{object.id}" } }
          end
        end
      stub_const(Chat, :MessagesSerializer, decorated) do
        native = native_message
        result = details(selection: "nodes { id excerpt }")
        expect(result["errors"]).to be_blank
        expect(result.dig("data", "chatMessages", "nodes", 0, "excerpt")).to eq(
          native.fetch("excerpt"),
        )
      end
    end

    it "selects nested thread instances without evaluating unselected renderers" do
      channel.update!(threading_enabled: true)
      thread = Fabricate(:chat_thread, channel: channel)
      reply = Fabricate(:chat_message, chat_channel: channel, thread: thread)
      thread.update!(last_message: reply, replies_count: 1)
      restricted =
        Class.new(Chat::ThreadSerializer) do
          def preview
            raise "Unselected preview unavailable"
          end

          def meta
            raise "Unselected metadata unavailable"
          end
        end
      stub_const(Chat, :ThreadSerializer, restricted) do
        result = details(selection: "nodes { thread { id } }")
        expect(result["errors"]).to be_blank
        expect(result.dig("data", "chatMessages", "nodes", 0, "thread", "id")).to eq(thread.id.to_s)
        result = details(selection: "nodes { thread { preview { lastReplyId } } }")
        expect(result.dig("errors", 0, "extensions", "code")).to eq("INTERNAL_ERROR")
      end
    end

    it "preserves distinct native thread history embedded original omission" do
      channel.update!(threading_enabled: true)
      thread = Fabricate(:chat_thread, channel: channel)
      result =
        details(thread_id: thread.id, selection: "nodes { thread { id originalMessage { id } } }")
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "chatThreadMessages", "nodes", 0, "thread")).to eq(
        "id" => thread.id.to_s,
        "originalMessage" => nil,
      )
      result = details(selection: "nodes { thread { id originalMessage { id } } }")
      expect(result["errors"]).to be_blank
      expect(
        result.dig("data", "chatMessages", "nodes", 0, "thread", "originalMessage", "id"),
      ).to eq(thread.original_message_id.to_s)
    end

    it "rejects collection bounds and changed native mention content" do
      mentioned = Fabricate.times(2, :user)
      mentioned.each { |actor| Fabricate(:user_chat_mention, chat_message: message, user: actor) }
      result = details(selection: "nodes { mentionedUsers(first: 1) { pageInfo { endCursor } } }")
      cursor =
        result.dig("data", "chatMessages", "nodes", 0, "mentionedUsers", "pageInfo", "endCursor")
      expect(cursor).to be_present
      [0, 51].each do |first|
        result = details(selection: "nodes { mentionedUsers(first: #{first}) { nodes { id } } }")
        expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      end
      mentioned.first.update!(username: "changed_mention")

      result =
        details(
          selection:
            "nodes { mentionedUsers(first: 1, after: #{cursor.to_json}) { nodes { id } } }",
        )

      expect(result.dig("data", "chatMessages", "nodes", 0, "mentionedUsers")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
    end

    it "binds block child continuation to the native public block fingerprint" do
      message.update!(
        blocks: [
          {
            type: "confirmation",
            title: "Before",
            question: "Continue?",
            parameters: [{ label: "First", value: "One" }, { label: "Second", value: "Two" }],
            elements: [],
          },
        ],
      )
      result =
        details(
          selection:
            "nodes { blocks(first: 1) { nodes { parameters(first: 1) { nodes { label value } pageInfo { endCursor } } } } }",
        )
      expect(result["errors"]).to be_blank
      cursor =
        result.dig(
          "data",
          "chatMessages",
          "nodes",
          0,
          "blocks",
          "nodes",
          0,
          "parameters",
          "pageInfo",
          "endCursor",
        )
      expect(cursor).to be_present
      selection =
        "nodes { blocks(first: 1) { nodes { parameters(first: 1, after: #{cursor.to_json}) { nodes { label value } } } } }"
      result = details(selection: selection)
      expect(result["errors"]).to be_blank
      expect(
        result.dig("data", "chatMessages", "nodes", 0, "blocks", "nodes", 0, "parameters", "nodes"),
      ).to eq([{ "label" => "Second", "value" => "Two" }])
      updated = message.blocks.deep_dup
      updated.first["title"] = "After"
      message.update!(blocks: updated)

      result = details(selection: selection)

      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
    end

    it "keeps native parent only restrictions authoritative for embedded media" do
      upload = Fabricate(:upload)
      message.uploads = [upload]
      restricted =
        Class.new(Chat::MessageSerializer) do
          def initialize(object, options = {})
            super(object, options.merge(only: %i[id chat_channel_id uploads]))
          end
        end
      stub_const(Chat, :MessageSerializer, restricted) do
        native = native_message.fetch("uploads").first
        expect(native).not_to have_key("url")
        result =
          details(selection: "nodes { uploads(first: 1) { nodes { id url originalFilename } } }")
        expect(result["errors"]).to be_blank
        expect(result.dig("data", "chatMessages", "nodes", 0, "uploads", "nodes", 0)).to eq(
          "id" => upload.id.to_s,
          "url" => nil,
          "originalFilename" => nil,
        )
      end
    end

    it "keeps private button values outside the typed schema" do
      get "/discourse-graphql/graphql",
          params: {
            query: '{ __type(name: "ChatButtonElement") { fields { name } } }',
          },
          headers: headers
      expect(response.parsed_body["errors"]).to be_blank
      expect(
        response.parsed_body.dig("data", "__type", "fields").map { |field| field.fetch("name") },
      ).to contain_exactly("type", "actionId", "text", "style", "icon")
    end

    it "preserves native flag permissions across category permission changes and Guardian denial" do
      selection = "nodes { availableFlags }"
      permitted = native_message.fetch("available_flags")
      expect(permitted).to be_present
      expect(
        details(selection: selection).dig("data", "chatMessages", "nodes", 0, "availableFlags"),
      ).to eq(permitted)

      channel.chatable.set_permissions(everyone: :readonly)
      channel.chatable.save!
      SiteSetting.chat_allowed_groups =
        "#{Group::AUTO_GROUPS[:everyone]}|#{Group::AUTO_GROUPS[:anonymous_users]}"
      denied = native_message.fetch("available_flags")
      expect(denied).to eq([])
      expect(
        details(selection: selection).dig("data", "chatMessages", "nodes", 0, "availableFlags"),
      ).to eq(denied)

      channel.chatable.set_permissions(everyone: :full)
      channel.chatable.save!
      Guardian.any_instance.stubs(:can_modify_channel_message?).returns(false)
      denied = native_message.fetch("available_flags")
      expect(denied).to eq([])
      expect(
        details(selection: selection).dig("data", "chatMessages", "nodes", 0, "availableFlags"),
      ).to eq(denied)
    end

    it "preserves native flag permission for an anonymous mode actor" do
      SiteSetting.allow_anonymous_mode = true
      SiteSetting.allow_chat_in_anonymous_mode = true
      SiteSetting.anonymous_posting_allowed_groups = Group::AUTO_GROUPS[:everyone]
      SiteSetting.chat_message_flag_allowed_groups = Group::AUTO_GROUPS[:everyone]
      shadow = AnonymousShadowCreator.get(user)
      expect(shadow).to be_present
      shadow_key = Fabricate(:api_key, user: shadow)
      shadow_headers = { "Api-Key" => shadow_key.key, "Api-Username" => shadow.username }
      get "/chat/api/channels/#{channel.id}/messages.json",
          params: {
            page_size: 1,
            direction: "past",
          },
          headers: shadow_headers
      expect(response.status).to eq(200)
      native_flags = response.parsed_body.fetch("messages").last.fetch("available_flags")
      expect(native_flags).to be_present

      result = details(selection: "nodes { availableFlags }", request_headers: shadow_headers)

      expect(result["errors"]).to be_blank
      expect(result.dig("data", "chatMessages", "nodes", 0, "availableFlags")).to eq(native_flags)
    end

    it "preserves omitted native message collections without inventing empty pages" do
      restricted =
        Class.new(Chat::MessageSerializer) do
          def include_mentioned_users?
            false
          end

          def include_uploads?
            false
          end

          def include_blocks?
            false
          end
        end
      stub_const(Chat, :MessageSerializer, restricted) do
        result =
          details(
            selection:
              "nodes { mentionedUsers { totalCount } uploads { totalCount } blocks { totalCount } }",
          )
        expect(result["errors"]).to be_blank
        expect(result.dig("data", "chatMessages", "nodes", 0)).to eq(
          "mentionedUsers" => nil,
          "uploads" => nil,
          "blocks" => nil,
        )
      end
    end

    it "rejects multiplied block rendering before native history work" do
      queries =
        track_sql_queries do
          result = details(last: 50, selection: "nodes { blocks(first: 5) { nodes { type } } }")
          expect(result.dig("errors", 0, "extensions", "code")).to eq("QUERY_TOO_COMPLEX")
        end
      expect(queries.grep(/FROM "chat_messages"/i)).to eq([])
    end

    it "bounds SQL growth across fifty authors, mentions, bookmarks and reply previews" do
      SiteSetting.enable_user_status = true
      SiteSetting.chat_pinned_messages = true
      entries =
        Array.new(50) do
          sender = Fabricate(:user)
          entry =
            Fabricate(:chat_message, chat_channel: channel, user: sender, in_reply_to: message)
          Fabricate(:user_chat_mention, chat_message: entry)
          Fabricate(:bookmark, user: user, bookmarkable: entry)
          entry
        end
      selection =
        "nodes { id author { id username status { description } } edited pinned availableFlags bookmark { id } inReplyTo { id user { id } } mentionedUsers(first: 1) { nodes { id username } } }"
      [1, 50].each do |last|
        expect(details(last: last, selection: selection)["errors"]).to be_blank
      end
      counts =
        [1, 50].map do |last|
          queries =
            track_sql_queries do
              result = details(last: last, selection: selection)
              expect(result["errors"]).to be_blank
              expect(result.dig("data", "chatMessages", "nodes").size).to eq(last)
            end
          tables = queries.group_by { |sql| sql[/FROM "([^"]+)"/i, 1] }.transform_values(&:size)
          puts(
            {
              measurement: "chat_message_presentation_tables",
              messages: last,
              tables: tables,
            }.to_json,
          )
          queries.count { |sql| sql.match?(/\A\s*(SELECT|WITH)\b/i) }
        end
      puts(
        {
          measurement: "chat_message_presentation_sql",
          messages: [1, 50],
          queries: counts,
        }.to_json,
      )
      expect(counts.last).to be <= counts.first + 3
    end

    it "accepts both previously signed native history cursor formats" do
      older = Fabricate(:chat_message, chat_channel: channel, created_at: 1.minute.from_now)
      newest = Fabricate(:chat_message, chat_channel: channel, created_at: 2.minutes.from_now)
      payload = {
        "channel_id" => channel.id.to_s,
        "last" => 1,
        "message_id" => newest.id,
        "created_at" => newest.created_at.iso8601(6),
        "actor_id" => user.id,
        "site" => RailsMultisite::ConnectionManagement.current_db,
      }
      cursor =
        Rails.application.message_verifier("discourse_graphql_chat_history").generate(payload)
      result = details(selection: "nodes { id }", before: cursor)
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "chatMessages", "nodes", 0, "id")).to eq(older.id.to_s)
      channel.update!(threading_enabled: true)
      thread = Fabricate(:chat_thread, channel: channel)
      thread_reply = Fabricate(:chat_message, chat_channel: channel, thread: thread)
      thread.update!(last_message: thread_reply)
      payload.merge!(
        "thread_id" => thread.id.to_s,
        "message_id" => thread_reply.id,
        "created_at" => thread_reply.created_at.iso8601(6),
      )
      cursor =
        Rails
          .application
          .message_verifier("discourse_graphql_chat_thread_history")
          .generate(payload)
      result = details(thread_id: thread.id, selection: "nodes { id }", before: cursor)
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "chatThreadMessages", "nodes", 0, "id")).to eq(
        thread.original_message_id.to_s,
      )
    end
  end

  private

  def details(
    selection:,
    channel_id: channel.id,
    thread_id: nil,
    last: 1,
    before: nil,
    request_headers: headers
  )
    field = thread_id.nil? ? "chatMessages" : "chatThreadMessages"
    arguments = "channelId: #{channel_id.to_s.to_json}, last: #{last}"
    arguments += ", threadId: #{thread_id.to_s.to_json}" unless thread_id.nil?
    arguments += ", before: #{before.to_json}" unless before.nil?
    get "/discourse-graphql/graphql",
        params: {
          query: "{ #{field}(#{arguments}) { #{selection} } currentUser { id } }",
        },
        headers: request_headers
    expect(response.status).to eq(200)
    response.parsed_body
  end

  def native_message(channel_id: channel.id)
    get "/chat/api/channels/#{channel_id}/messages.json",
        params: {
          page_size: 1,
          direction: "past",
        },
        headers: headers
    expect(response.status).to eq(200)
    response.parsed_body.fetch("messages").last
  end
end
