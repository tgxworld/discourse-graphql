# Native dependencies

Supported Discourse revision: `f5e1933dd40c57b886da02c45e5630020ceb99c2`.

## Anonymous Chat history after anchor deletion

Status: unresolved. This prevents complete Chat history acceptance.

With Chat enabled for anonymous public preview, the native message endpoint returns the latest public message successfully. After that message is deleted, requesting an older page with its ID as `target_message_id` returns HTTP 500. The exception is `NoMethodError: undefined method 'id' for nil` in `Chat::Channel::Policy::MessageExistence#call`, line 10.

The policy dereferences `guardian.user.id` for a deleted target, while an anonymous Guardian has no user. The smallest native correction must handle the anonymous actor explicitly while retaining native target recovery, channel authorization and moderator behavior. An author match must require an authenticated actor, because a deleted author ID and an anonymous actor ID can both be null. The GraphQL plugin must not copy or patch that permission policy.

Reproduced through real native HTTP requests with seed 23293:

1. Enable Chat for everyone and anonymous users.
2. Create a public category channel and two messages.
3. GET `/chat/api/channels/:id/messages?page_size=1`. It returns HTTP 200 and the newest message.
4. Delete that message through native model behavior.
5. GET `/chat/api/channels/:id/messages?page_size=1&direction=past&target_message_id=:deleted_id`. It returns HTTP 500 at the policy above.

The task reproduction is `tmp/discourse-task/native_chat_anchor_spec.rb` in the supported Discourse worktree. It fails at the second HTTP status assertion. It runs with:

```bash
tgx-dv test --name graphql-revival-01a1aaad --env LOAD_PLUGINS=1 --seed 23293 tmp/discourse-task/native_chat_anchor_spec.rb
```

GraphQL error containment does not resolve this dependency. Keep it incomplete until the native correction is present in the supported revision and the reproduction plus GraphQL recovery tests pass. Full application scope remains required.
