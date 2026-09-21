require "test_helper"

class CopyProjectJobTest < ActiveJob::TestCase
  class CountProjectsJob < ActiveJob::Base
    def perform = Project.count
  end

  class DiscardingCountProjectsJob < CountProjectsJob
    discard_on ActiveJob::DeserializationError
  end

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

    assert_raises(AccountScoping::MissingAccountError) { perform_enqueued_jobs }
  end

  test "jobs for a deleted account raise a DeserializationError" do
    account = Account.create!(name: "Deleted")
    Current.set(account: account) { CountProjectsJob.perform_later }
    account.destroy!

    error = assert_raises(ActiveJob::DeserializationError) { perform_enqueued_jobs }
    assert_kind_of ActiveRecord::RecordNotFound, error.cause
  end

  test "jobs for a deleted account can be discarded" do
    account = Account.create!(name: "Deleted")
    Current.set(account: account) { DiscardingCountProjectsJob.perform_later }
    account.destroy!

    assert_nothing_raised { perform_enqueued_jobs }
    assert_nil Current.account
  end
end
