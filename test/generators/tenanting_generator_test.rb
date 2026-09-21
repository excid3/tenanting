require "test_helper"

class TenantingGeneratorTest < Rails::Generators::TestCase
  tests TenantingGenerator
  destination File.expand_path("../../tmp/generator", __dir__)
  setup :prepare_destination

  test "generates tenanting without authentication" do
    create_app
    run_generator

    assert_file "app/models/account.rb" do |content|
      assert_no_match "has_many :memberships", content
      assert_match "def slug", content
    end
    assert_file "app/models/current.rb", /attribute :account, :all_accounts/
    assert_file "app/models/concerns/account_scoping.rb" do |content|
      assert_match "def scoped_to_account(through: nil, optional: false)", content
      assert_match "raise MissingAccountError", content
    end
    assert_file "app/models/application_record.rb", /  primary_abstract_class\n\n  include AccountScoping\n/
    assert_file "app/controllers/concerns/tenanting.rb", /Account\.find_by\(id: account_id\)/
    assert_file "app/controllers/application_controller.rb", /class ApplicationController < ActionController::Base\n  include Tenanting\n/
    assert_file "config/initializers/tenanting.rb" do |content|
      assert_match "module AccountSlug", content
      assert_match "module AccountScopedJob", content
      assert_match "IRB::HelperMethod.register :switch_to_account", content
      assert_no_match "Turbo", content
    end
    assert_migration "db/migrate/create_accounts.rb", /t\.string :name, null: false/

    assert_no_file "app/models/membership.rb"
    assert_no_file "app/controllers/accounts_controller.rb"
    assert_no_migration "db/migrate/create_memberships.rb"
  end

  test "generates memberships and the account picker with authentication" do
    create_app authentication: true
    run_generator

    assert_file "app/models/membership.rb"
    assert_file "app/models/account.rb", /has_many :users, through: :memberships/
    assert_file "app/models/user.rb", /has_many :sessions, dependent: :destroy\n  has_many :memberships, dependent: :destroy\n  has_many :accounts, through: :memberships\n/
    assert_file "app/models/current.rb", /attribute :account, :all_accounts\n  attribute :session/
    assert_file "app/controllers/concerns/tenanting.rb", /Current\.user&\.accounts&\.find_by\(id: account_id\)/
    assert_file "app/controllers/application_controller.rb", /include Authentication\n  include Tenanting\n/
    assert_file "app/controllers/sessions_controller.rb", /allow_accountless_access/
    assert_file "app/controllers/passwords_controller.rb", /allow_accountless_access/
    assert_file "app/controllers/accounts_controller.rb", /allow_accountless_access/
    assert_file "app/views/accounts/index.html.erb", /root_url\(script_name: account\.slug\)/
    assert_file "config/routes.rb", /resources :accounts, only: :index/
    assert_migration "db/migrate/create_memberships.rb", /add_index :memberships, %i\[ user_id account_id \], unique: true/
    assert_file "test/fixtures/memberships.yml"
  end

  test "renders Turbo Stream broadcasts in the account when turbo-rails is installed" do
    create_app turbo: true
    run_generator

    assert_file "config/initializers/tenanting.rb", /Turbo::StreamsChannel\.singleton_class\.prepend AccountScopedTurboStreams/
  end

  test "prefixes mailer URLs with the account" do
    create_app mailer: true
    run_generator

    assert_file "app/mailers/application_mailer.rb", /super\.merge\(script_name: Current\.account&\.slug\)/
  end

  test "adds the test helper" do
    create_app
    run_generator

    assert_file "test/fixtures/accounts.yml"
    assert_file "test/test_helpers/account_test_helper.rb", /def switch_to_account/
    assert_file "test/test_helper.rb", /require "rails\/test_help"\nrequire_relative "test_helpers\/account_test_helper"\n/
  end

  test "skips test files without a test_helper" do
    create_app test: false
    run_generator

    assert_no_file "test/test_helpers/account_test_helper.rb"
    assert_no_file "test/fixtures/accounts.yml"
  end

  private
    def create_app(authentication: false, turbo: false, mailer: false, test: true)
      write "Gemfile", <<~RUBY
        source "https://rubygems.org"
        gem "rails"
        #{'gem "turbo-rails"' if turbo}
      RUBY
      write "config/routes.rb", "Rails.application.routes.draw do\nend\n"
      write "app/models/application_record.rb", "class ApplicationRecord < ActiveRecord::Base\n  primary_abstract_class\nend\n"
      write "app/controllers/application_controller.rb", <<~RUBY
        class ApplicationController < ActionController::Base
        #{"  include Authentication" if authentication}
        end
      RUBY
      write "app/mailers/application_mailer.rb", "class ApplicationMailer < ActionMailer::Base\nend\n" if mailer
      write "test/test_helper.rb", %(require "rails/test_help"\n) if test

      if authentication
        write "app/controllers/concerns/authentication.rb", "module Authentication\nend\n"
        write "app/controllers/sessions_controller.rb", "class SessionsController < ApplicationController\nend\n"
        write "app/controllers/passwords_controller.rb", "class PasswordsController < ApplicationController\nend\n"
        write "app/models/user.rb", "class User < ApplicationRecord\n  has_many :sessions, dependent: :destroy\nend\n"
        write "app/models/current.rb", "class Current < ActiveSupport::CurrentAttributes\n  attribute :session\nend\n"
      end
    end

    def write(path, content)
      path = File.join(destination_root, path)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end
end

class TenantingGemTest < Minitest::Test
  # Bundler requires the gem in the app, which must not shadow the generated Tenanting concern.
  def test_requiring_the_gem_defines_no_constants
    require "tenanting"
    refute Object.const_defined?(:Tenanting, false)
  end
end
