# Native capability inventory

Supported Discourse revision: `f5e1933dd40c57b886da02c45e5630020ceb99c2`.

This snapshot contains 1467 routed action names, 345 controllers and 58 other endpoints. Counts describe investigation surfaces. Capability acceptance requires reviewed contracts and executed evidence.

## Owners and shared surfaces

| Owner | Routed actions | Settings | Shared surfaces |
|---|---|---|---|
| Core | 860 | 1109 | Core capabilities and native protocols |
| `automation` | 13 | 3 | Shared source audit pending |
| `blog` | 42 | 11 | Shared source audit pending |
| `boards` | 21 | 2 | Shared source audit pending |
| `chat` | 66 | 36 | Shared source audit pending |
| `checklist` | 1 | 1 | Shared source audit pending |
| `discourse-adplugin` | 9 | 132 | Shared source audit pending |
| `discourse-affiliate` | 0 | 17 | rendering, configuration |
| `discourse-ai` | 147 | 161 | Shared source audit pending |
| `discourse-apple-auth` | 0 | 5 | authentication provider, configuration |
| `discourse-assign` | 10 | 21 | Shared source audit pending |
| `discourse-cakeday` | 2 | 4 | Shared source audit pending |
| `discourse-captcha` | 5 | 9 | Shared source audit pending |
| `discourse-chat-integration` | 16 | 53 | Shared source audit pending |
| `discourse-data-explorer` | 21 | 3 | Shared source audit pending |
| `discourse-details` | 0 | 1 | rendering, configuration |
| `discourse-events` | 16 | 41 | Shared source audit pending |
| `discourse-gamification` | 10 | 18 | Shared source audit pending |
| `discourse-github` | 1 | 14 | Shared source audit pending |
| `discourse-graphviz` | 0 | 1 | rendering, configuration |
| `discourse-lazy-videos` | 0 | 4 | rendering, configuration |
| `discourse-local-dates` | 0 | 5 | rendering, calendar export, configuration |
| `discourse-login-with-amazon` | 0 | 8 | authentication provider, configuration |
| `discourse-lti` | 0 | 6 | authentication provider, signed launch protocol, role synchronization, configuration |
| `discourse-math` | 0 | 8 | rendering, configuration |
| `discourse-microsoft-auth` | 0 | 5 | authentication provider, configuration |
| `discourse-narrative-bot` | 1 | 8 | Shared source audit pending |
| `discourse-oauth2-basic` | 0 | 30 | authentication provider, configuration |
| `discourse-openid-connect` | 0 | 25 | authentication provider, logout protocol, configuration |
| `discourse-patreon` | 8 | 17 | Shared source audit pending |
| `discourse-policy` | 4 | 4 | Shared source audit pending |
| `discourse-post-voting` | 14 | 7 | Shared source audit pending |
| `discourse-presence` | 0 | 2 | presence, live delivery, configuration |
| `discourse-reactions` | 6 | 10 | Shared source audit pending |
| `discourse-rewind` | 3 | 1 | Shared source audit pending |
| `discourse-rss-polling` | 10 | 6 | Shared source audit pending |
| `discourse-solved` | 5 | 20 | Shared source audit pending |
| `discourse-subscriptions` | 33 | 21 | Shared source audit pending |
| `discourse-templates` | 2 | 6 | Shared source audit pending |
| `discourse-topic-voting` | 5 | 11 | Shared source audit pending |
| `discourse-user-notes` | 3 | 3 | Shared source audit pending |
| `discourse-workflows` | 72 | 9 | Shared source audit pending |
| `discourse-zendesk-plugin` | 2 | 13 | Shared source audit pending |
| `footnote` | 0 | 2 | rendering, configuration |
| `live` | 53 | 50 | Shared source audit pending |
| `poll` | 5 | 9 | Shared source audit pending |
| `spoiler-alert` | 0 | 1 | rendering, configuration |
| `styleguide` | 1 | 3 | developer page access, configuration, site capability metadata |

## Existing GraphQL mappings

These links cover declared adapter slices. The remaining native action capabilities stay incomplete.

| Native action | GraphQL fields | Status |
|---|---|---|
| `bookmarks#bulk` | `mutation.bulkBookmarks` | partial |
| `bookmarks#create` | `mutation.createBookmark` | partial |
| `bookmarks#destroy` | `mutation.deleteBookmark` | partial |
| `bookmarks#toggle_pin` | `mutation.toggleBookmarkPin` | partial |
| `bookmarks#update` | `mutation.updateBookmark` | partial |
| `categories#index` | `query.categories` | partial |
| `chat/api/channel_messages#create` | `mutation.createChatMessage` | partial |
| `chat/api/channel_messages#index` | `query.chatMessages` | partial |
| `chat/api/channels#index` | `query.chatChannels` | partial |
| `chat/api/channels#show` | `query.chatChannel` | partial |
| `chat/api/channels_current_user_membership#create` | `mutation.joinChatChannel` | partial |
| `chat/api/channels_current_user_membership#destroy` | `mutation.leaveChatChannel` | partial |
| `chat/api/channels_current_user_membership#update` | `mutation.starChatChannel` | partial |
| `chat/api/channels_current_user_membership_follows#destroy` | `mutation.unfollowChatChannel` | partial |
| `chat/api/channels_current_user_notifications_settings#update` | `mutation.updateChatNotifications` | partial |
| `chat/api/channels_read#update` | `mutation.markChatRead` | partial |
| `chat/api/channels_read#update_all` | `mutation.markAllChatRead` | partial |
| `list#latest` | `query.latestTopics` | partial |
| `notifications#index` | `query.notifications` | partial |
| `notifications#mark_read` | `mutation.markNotificationRead`, `mutation.markAllNotificationsRead` | partial |
| `posts#create` | `mutation.createTopic`, `mutation.createPost` | partial |
| `search#query` | `query.search` | partial |
| `session#current` | `query.currentUser` | partial |
| `topics#destroy_timings` | `mutation.resetTopicReading` | partial |
| `topics#set_notifications` | `mutation.updateTopicNotifications` | partial |
| `topics#show` | `query.topic`, `query.topicPosts` | partial |
| `topics#timings` | `mutation.recordTopicTimings` | partial |
| `users#bookmarks` | `query.bookmarks` | partial |

## Native route resolution

These entries need their native capability assessment retained. A resource route with no Ruby action does not establish a GraphQL operation.

| Native route | Resolution name | Assessment |
|---|---|---|
| `discourse_ai/admin/ai_agents#indexing_status_check` | `indexing_status_check` | route without Ruby action, capability assessment pending |
| `discourse_ai/admin/ai_agents#remove_file` | `remove_file` | route without Ruby action, capability assessment pending |
| `discourse_assign/assign#claim` | `claim` | route without Ruby action, capability assessment pending |
| `discourse_reactions/custom_reactions#index` | `index` | route without Ruby action, capability assessment pending |
| `discourse_subscriptions/admin/plans#destroy` | `destroy` | route without Ruby action, capability assessment pending |
| `discourse_subscriptions/admin/plans#edit` | `edit` | route without Ruby action, capability assessment pending |
| `discourse_subscriptions/admin/plans#new` | `new` | route without Ruby action, capability assessment pending |
| `discourse_subscriptions/admin/products#edit` | `edit` | route without Ruby action, capability assessment pending |
| `discourse_subscriptions/admin/products#new` | `new` | route without Ruby action, capability assessment pending |
| `live/rooms#edit` | `edit` | route without Ruby action, capability assessment pending |
| `live/rooms#new` | `new` | route without Ruby action, capability assessment pending |
| `message_bus#poll` | `MessageBusController` | native middleware protocol |
| `post_voting/votes#edit` | `edit` | route without Ruby action, capability assessment pending |
| `post_voting/votes#new` | `new` | route without Ruby action, capability assessment pending |
| `post_voting/votes#show` | `show` | route without Ruby action, capability assessment pending |
| `post_voting/votes#update` | `update` | route without Ruby action, capability assessment pending |
