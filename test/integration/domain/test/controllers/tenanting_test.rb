require "test_helper"

class TenantingTest < ActionDispatch::IntegrationTest
  test "URLs use the account's host" do
    switch_to_account accounts(:one)
    assert_equal "http://one.example.com/projects", projects_url
  end

  test "resolves the account from the subdomain" do
    switch_to_account accounts(:one)
    sign_in_as users(:one)

    get "/projects"
    assert_response :success
    assert_match "Project One", response.body
    assert_equal "one.example.com", request.host
  end

  test "resolves the account from a custom domain" do
    accounts(:one).update!(domain: "projects.one.test")
    switch_to_account accounts(:one)
    sign_in_as users(:one)

    get "/projects"
    assert_response :success
    assert_match "Project One", response.body
    assert_equal "http://projects.one.test/projects", projects_url
  end

  test "sign ins belong to a host" do
    accounts(:two).memberships.create!(user: users(:one))
    switch_to_account accounts(:one)
    sign_in_as users(:one)
    switch_to_account accounts(:two)

    get "/projects"
    assert_redirected_to "http://two.example.com/session/new"
  end

  test "can't access an account you aren't a member of" do
    switch_to_account accounts(:two)
    sign_in_as users(:one)

    get "/projects"
    assert_response :not_found
  end

  test "unknown subdomains are not found" do
    host! "nope.example.com"
    sign_in_as users(:one)

    get "/projects"
    assert_response :not_found
  end

  test "requests on the app's domain go to the account picker" do
    sign_in_as users(:one)

    get "/projects"
    assert_redirected_to "http://www.example.com/accounts"

    follow_redirect!
    assert_redirected_to "http://one.example.com/"
  end

  test "account picker lists accounts when there are several" do
    accounts(:two).memberships.create!(user: users(:one))
    sign_in_as users(:one)

    get accounts_url
    assert_response :success
    assert_select "a[href=?]", "http://two.example.com/"
  end

  test "authentication pages don't require an account" do
    host! "one.example.com"

    get new_session_url
    assert_response :success
  end
end
