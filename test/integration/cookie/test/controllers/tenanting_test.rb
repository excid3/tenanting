require "test_helper"

class TenantingTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
  end

  test "URLs are not prefixed with the account" do
    switch_to_account accounts(:one)
    assert_equal "http://www.example.com/projects", projects_url
  end

  test "requests without an account go to the account picker" do
    get projects_url
    assert_redirected_to accounts_url

    follow_redirect!
    assert_select "form[action=?]", account_switch_path(accounts(:one))

    post account_switch_url(accounts(:one))
    follow_redirect!
    assert_match "Project One", response.body
  end

  test "account picker lists accounts when there are several" do
    accounts(:two).memberships.create!(user: users(:one))

    get accounts_url
    assert_response :success
    assert_select "form[action=?]", account_switch_path(accounts(:two))
  end

  test "switching accounts" do
    accounts(:two).memberships.create!(user: users(:one))
    switch_to_account accounts(:one)

    post account_switch_url(accounts(:two))
    assert_redirected_to root_url

    get projects_url
    assert_match "Project Two", response.body
    assert_no_match "Project One", response.body
  end

  test "can't switch to an account you aren't a member of" do
    post account_switch_url(accounts(:two))
    assert_response :not_found
  end

  test "an account cookie for an account you aren't a member of is ignored" do
    switch_to_account accounts(:two)

    get projects_url
    assert_redirected_to accounts_url
  end

  test "authentication pages don't require an account" do
    get new_session_url
    assert_response :success
  end
end
