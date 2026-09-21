require "test_helper"

class ProjectMailerTest < ActionMailer::TestCase
  test "links point into the account the email was sent from" do
    Current.set(account: accounts(:one)) { ProjectMailer.created(projects(:one)).deliver_later }

    perform_enqueued_jobs
    assert_match "http://example.com/#{accounts(:one).id}/projects/#{projects(:one).id}", ActionMailer::Base.deliveries.last.body.to_s
  end
end
