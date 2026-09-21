require "test_helper"
require "turbo/broadcastable/test_helper"

class ProjectBroadcastTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper

  test "later broadcasts render in the account they were enqueued from" do
    Current.set(account: accounts(:two)) do
      Turbo::StreamsChannel.broadcast_append_later_to "projects", target: "projects", partial: "projects/link", locals: { project: projects(:two) }
    end

    broadcasts = capture_turbo_stream_broadcasts("projects") { perform_enqueued_jobs }
    assert_equal "/projects/#{projects(:two).id}", broadcasts.last.at_css("a")["href"]
  end
end
