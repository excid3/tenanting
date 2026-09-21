require "test_helper"

class AccountScopingTest < ActiveSupport::TestCase
  # scoped_to_account

  test "queries raise without a current account" do
    error = assert_raises(AccountScoping::MissingAccountError) { Project.count }
    assert_match "Project is scoped to an account", error.message
  end

  test "building records raises without a current account" do
    assert_raises(AccountScoping::MissingAccountError) { Project.new(name: "New", account: accounts(:one)) }
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
    assert_equal 2, AccountScoping.across_accounts { Project.count }
    assert_raises(AccountScoping::MissingAccountError) { Project.count }
  end

  test "across_accounts wins over the current account" do
    switch_to_account accounts(:one)
    assert_equal 2, AccountScoping.across_accounts { Project.count }
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

  test "an account is required" do
    project = AccountScoping.across_accounts { Project.new(name: "Orphan") }

    assert_not project.valid?
    assert_includes project.errors[:account], "must exist"
  end

  test "bulk updates and deletes are scoped" do
    switch_to_account accounts(:one)
    Project.update_all(name: "Renamed")
    Comment.delete_all
    Task.delete_all
    Project.delete_all

    assert_equal [ projects(:two) ], AccountScoping.across_accounts { Project.all.to_a }
    assert_equal "Project Two", AccountScoping.across_accounts { projects(:two).reload.name }
  end

  test "instance updates include the account in the query" do
    project = projects(:one)
    switch_to_account accounts(:two)

    assert_equal 0, Project.where(id: project.id).update_all(name: "Nope")
    assert_equal "Project One", Project.unscoped.find(project.id).name
  end

  test "models that aren't scoped are unaffected" do
    assert_not Account.scoped_to_account?
    assert_equal 2, Account.count
  end

  # scoped_to_account through:

  test "through models are scoped by their parent" do
    switch_to_account accounts(:one)

    assert_equal [ tasks(:one) ], Task.all.to_a
    assert_raises(ActiveRecord::RecordNotFound) { Task.find(tasks(:two).id) }
  end

  test "through models can be nested" do
    switch_to_account accounts(:one)

    assert_equal [ comments(:one) ], Comment.all.to_a
    assert_raises(ActiveRecord::RecordNotFound) { Comment.find(comments(:two).id) }
  end

  test "through models raise without a current account" do
    assert_raises(AccountScoping::MissingAccountError) { Task.count }
    assert_raises(AccountScoping::MissingAccountError) { Comment.count }
    assert_equal 2, AccountScoping.across_accounts { Comment.count }
  end

  test "through models get their account from their parent" do
    switch_to_account accounts(:one)

    assert_equal accounts(:one), comments(:one).account
    assert_equal accounts(:one).id, comments(:one).account_id
    assert_equal accounts(:one), projects(:one).tasks.build.account
  end

  test "through models can't be created under another account's parent" do
    switch_to_account accounts(:one)
    task = Task.new(title: "Sneaky", project_id: projects(:two).id)

    assert_not task.valid?
    assert_includes task.errors[:project], "must belong to the current account"
  end

  test "through models can't move to another account" do
    AccountScoping.across_accounts do
      task = tasks(:one)
      task.project = projects(:two)

      assert_not task.valid?
      assert_includes task.errors[:project], "must belong to the same account"
    end
  end

  test "through models can move within their account" do
    switch_to_account accounts(:one)
    task = tasks(:one)
    task.update!(project: Project.create!(name: "Other"))

    assert_equal accounts(:one), task.reload.account
  end

  test "bulk updates and deletes are scoped for through models" do
    switch_to_account accounts(:one)
    Task.update_all(title: "Renamed")
    Comment.delete_all

    AccountScoping.across_accounts do
      assert_equal [ comments(:two) ], Comment.all.to_a
      assert_equal "Task Two", tasks(:two).reload.title
    end
  end

  test "through: can't be combined with optional:" do
    error = assert_raises(ArgumentError) { Class.new(ApplicationRecord) { scoped_to_account through: :project, optional: true } }
    assert_match "Make the project association optional instead", error.message
  end

  # scoped_to_account optional:

  test "optional records without an account can exist outside of accounts" do
    tag = AccountScoping.across_accounts { Tag.create!(name: "Global") }
    assert_nil tag.account
  end

  test "optional records without an account are hidden in an account" do
    switch_to_account accounts(:one)
    assert_equal [ tags(:one) ], Tag.all.to_a
  end

  test "optional records created in an account always belong to it" do
    switch_to_account accounts(:one)
    tag = Tag.create!(name: "Sneaky", account: nil)

    assert_equal accounts(:one), tag.account
  end

  test "optional records can't be created in another account" do
    switch_to_account accounts(:one)
    tag = Tag.new(name: "Sneaky", account: accounts(:two))

    assert_not tag.valid?
    assert_includes tag.errors[:account], "must be the current account"
  end

  test "optional records can be read alongside the account's records explicitly" do
    switch_to_account accounts(:one)
    tags = AccountScoping.across_accounts { Tag.where(account: [ Current.account, nil ]).order(:name).to_a }

    assert_equal [ tags(:shared), tags(:one) ], tags
  end

  # belongs_to validations

  test "belongs_to associations must be in the same account" do
    switch_to_account accounts(:one)
    task = tasks(:one)
    task.tag = tags(:two) # Fixture accessors load unscoped

    assert_not task.valid?
    assert_includes task.errors[:tag], "must belong to the same account"
  end

  test "belongs_to associations can't reference another account's records by id" do
    switch_to_account accounts(:one)
    task = tasks(:one)
    task.tag_id = tags(:two).id

    assert_not task.valid?
    assert_includes task.errors[:tag], "must belong to the same account"
  end

  test "belongs_to associations in the same account are valid" do
    switch_to_account accounts(:one)
    assert tasks(:one).update(tag: tags(:one))
  end
end
