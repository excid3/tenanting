require "test_helper"

class CopyProjectJobTest < ActiveJob::TestCase
  test "jobs run in the account they were enqueued from" do
    Current.set(account: accounts(:two)) { CopyProjectJob.perform_later(projects(:two)) }

    assert_equal accounts(:two).to_global_id.to_s, enqueued_jobs.last["current_account"]
    assert_nil Current.account

    perform_enqueued_jobs
    copy = Project.unscoped.find_by!(name: "Project Two (copy)")
    assert_equal accounts(:two), copy.account
  end

  test "jobs enqueued without an account raise when they query" do
    CopyProjectJob.perform_later(projects(:one))

    assert_raises(AccountScoped::MissingAccountError) { perform_enqueued_jobs }
  end
end
