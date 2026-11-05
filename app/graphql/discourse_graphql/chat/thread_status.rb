module DiscourseGraphQL
  module Chat
    class ThreadStatus < Types::BaseEnum
      graphql_name "ChatThreadStatus"
      ::Chat::Thread.statuses.each_key { |status| value status.upcase, value: status }
    end
  end
end
