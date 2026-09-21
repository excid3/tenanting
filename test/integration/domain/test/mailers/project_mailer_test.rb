require "test_helper"

class ProjectMailerTest < ActionMailer::TestCase
  test "links point to the domain of the account the email was sent from" do
    Current.set(account: accounts(:one)) { ProjectMailer.created(projects(:one)).deliver_later }

    perform_enqueued_jobs
    assert_match "http://one.example.com/projects/#{projects(:one).id}", ActionMailer::Base.deliveries.last.body.to_s
  end

  test "links use the account's custom domain" do
    accounts(:one).update!(domain: "projects.one.test")
    Current.set(account: accounts(:one)) { ProjectMailer.created(projects(:one)).deliver_now }

    assert_match "http://projects.one.test/projects/#{projects(:one).id}", ActionMailer::Base.deliveries.last.body.to_s
  end
end
