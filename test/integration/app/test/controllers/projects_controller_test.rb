require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:one)
    sign_in_as users(:one)
    switch_to_account accounts(:one)
  end

  test "URLs are prefixed with the account" do
    assert_equal "http://www.example.com/#{accounts(:one).id}/projects", projects_url
  end

  test "should get index" do
    get projects_url
    assert_response :success
    assert_match "Project One", response.body
    assert_no_match "Project Two", response.body
  end

  test "should create project" do
    assert_difference("Project.count") do
      post projects_url, params: { project: { name: "New" } }
    end

    assert_redirected_to "http://www.example.com/#{accounts(:one).id}/projects/#{Project.last.id}"
    assert_equal accounts(:one), Project.last.account
  end

  test "can't create a project in another account through params" do
    assert_no_difference("Project.count") do
      post projects_url, params: { project: { name: "Sneaky", account_id: accounts(:two).id } }
    end
    assert_response :unprocessable_entity
  end

  test "can't access another account's project" do
    get project_url(projects(:two))
    assert_response :not_found
  end

  test "should update project" do
    patch project_url(@project), params: { project: { name: "Updated" } }
    assert_redirected_to project_url(@project)
    assert_equal "Updated", @project.reload.name
  end

  test "should destroy project" do
    assert_difference("Project.count", -1) do
      delete project_url(@project)
    end
    assert_redirected_to projects_url
  end

  test "the account is restored after each request" do
    get projects_url
    assert_equal accounts(:one), Current.account
    assert_equal 1, Project.count
  end
end

class TenantingTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
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
