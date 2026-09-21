require "test_helper"
require "turbo/broadcastable/test_helper"

class ProjectBroadcastTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper

  test "broadcasts render links into the account" do
    switch_to_account accounts(:one)
    Turbo::StreamsChannel.broadcast_append_to "projects", target: "projects", partial: "projects/link", locals: { project: projects(:one) }

    assert_equal project_path, capture_turbo_stream_broadcasts("projects").last.at_css("a")["href"]
  end

  test "later broadcasts render links into the account they were enqueued from" do
    Current.set(account: accounts(:two)) do
      Turbo::StreamsChannel.broadcast_append_later_to "projects", target: "projects", partial: "projects/link", locals: { project: projects(:two) }
    end

    broadcasts = capture_turbo_stream_broadcasts("projects") { perform_enqueued_jobs }
    assert_equal "/#{accounts(:two).id}/projects/#{projects(:two).id}", broadcasts.last.at_css("a")["href"]
  end

  private
    def project_path
      "/#{accounts(:one).id}/projects/#{projects(:one).id}"
    end
end
