require "test_helper"

class TenantingTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
  end

  test "URLs are prefixed with the account" do
    switch_to_account accounts(:one)
    assert_equal "http://www.example.com/#{accounts(:one).id}/projects", projects_url
  end

  test "resolves the account from the path" do
    get "/#{accounts(:one).id}/projects"
    assert_response :success
    assert_match "Project One", response.body
  end

  test "can't access an account you aren't a member of" do
    get "/#{accounts(:two).id}/projects"
    assert_response :not_found
  end

  test "requests without an account go to the account picker" do
    get "/projects"
    assert_redirected_to accounts_url

    follow_redirect!
    assert_redirected_to "http://www.example.com/#{accounts(:one).id}/"
  end

  test "account picker lists accounts when there are several" do
    accounts(:two).memberships.create!(user: users(:one))

    get accounts_url
    assert_response :success
    assert_select "a[href=?]", "http://www.example.com/#{accounts(:two).id}/"
  end

  test "authentication pages don't require an account" do
    get new_session_url
    assert_response :success
  end
end
