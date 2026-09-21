require "test_helper"

class AccountScopedTest < ActiveSupport::TestCase
  test "queries raise without a current account" do
    error = assert_raises(AccountScoped::MissingAccountError) { Project.count }
    assert_match "Project is scoped to an account", error.message
  end

  test "building records raises without a current account" do
    assert_raises(AccountScoped::MissingAccountError) { Project.new(name: "New", account: accounts(:one)) }
  end

  test "queries are scoped to the current account" do
    switch_to_account accounts(:one)

    assert_equal [ projects(:one) ], Project.all.to_a
    assert_raises(ActiveRecord::RecordNotFound) { Project.find(projects(:two).id) }
  end

  test "new records are assigned to the current account" do
    switch_to_account accounts(:one)
    assert_equal accounts(:one), Project.create!(name: "New").account
  end

  test "Current.set scopes a block to an account" do
    Current.set(account: accounts(:two)) do
      assert_equal [ projects(:two) ], Project.all.to_a
    end
    assert_nil Current.account
  end

  test "across_accounts queries every account" do
    assert_equal 2, AccountScoped.across_accounts { Project.count }
    assert_raises(AccountScoped::MissingAccountError) { Project.count }
  end

  test "across_accounts wins over the current account" do
    switch_to_account accounts(:one)
    assert_equal 2, AccountScoped.across_accounts { Project.count }
    assert_equal 1, Project.count
  end

  test "can't assign another account while one is current" do
    switch_to_account accounts(:one)
    project = Project.new(name: "Sneaky", account_id: accounts(:two).id)

    assert_not project.valid?
    assert_includes project.errors[:account], "must be the current account"
  end

  test "account can't be changed" do
    project = projects(:one)
    project.account = accounts(:two)

    assert_not project.valid?
    assert_includes project.errors[:account], "can't be changed"
  end

  test "belongs_to associations must be in the same account" do
    switch_to_account accounts(:one)
    task = Task.new(title: "Cross", project: projects(:two)) # Fixture accessors load unscoped

    assert_not task.valid?
    assert_includes task.errors[:project], "must belong to the same account"
  end

  test "can't reference another account's records by id" do
    switch_to_account accounts(:one)
    task = Task.new(title: "Cross", project_id: projects(:two).id)

    assert_not task.valid?
  end

  test "bulk updates and deletes are scoped" do
    switch_to_account accounts(:one)
    Project.update_all(name: "Renamed")
    Task.delete_all
    Project.delete_all

    assert_equal [ projects(:two) ], AccountScoped.across_accounts { Project.all.to_a }
    assert_equal "Project Two", AccountScoped.across_accounts { projects(:two).reload.name }
  end

  test "instance updates include the account in the query" do
    project = projects(:one)
    switch_to_account accounts(:two)

    assert_equal 0, Project.where(id: project.id).update_all(name: "Nope")
    assert_equal "Project One", Project.unscoped.find(project.id).name
  end
end
