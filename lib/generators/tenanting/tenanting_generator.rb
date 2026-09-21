# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

# Generates multitenancy into an app the same way `bin/rails generate authentication`
# generates authentication: plain application code built on Current attributes,
# concerns, and a middleware, which the app owns and can edit.
class TenantingGenerator < Rails::Generators::Base
  include ActiveRecord::Generators::Migration

  source_root File.expand_path("templates", __dir__)

  def create_tenanting_files
    template "app/models/account.rb"
    template "app/models/concerns/account_scoped.rb"
    template "app/controllers/concerns/tenanting.rb"
    template "config/initializers/tenanting.rb"

    if authentication?
      template "app/models/membership.rb"
      template "app/controllers/accounts_controller.rb"
      template "app/views/accounts/index.html.erb"
    end
  end

  def configure_current
    if exist?("app/models/current.rb")
      inject_into_class "app/models/current.rb", "Current", "  attribute :account, :all_accounts\n"
    else
      template "app/models/current.rb"
    end
  end

  def configure_user
    if authentication?
      inject_into_file "app/models/user.rb", <<~RUBY.indent(2), after: "has_many :sessions, dependent: :destroy\n"
        has_many :memberships, dependent: :destroy
        has_many :accounts, through: :memberships
      RUBY
    end
  end

  def configure_controllers
    if authentication?
      # Tenanting has to run after Authentication so it can check the user's memberships.
      inject_into_file "app/controllers/application_controller.rb", "  include Tenanting\n", after: "  include Authentication\n"

      %w[ sessions passwords ].each do |name|
        path = "app/controllers/#{name}_controller.rb"
        inject_into_class path, "#{name.camelize}Controller", "  allow_accountless_access\n" if exist?(path)
      end
    else
      inject_into_class "app/controllers/application_controller.rb", "ApplicationController", "  include Tenanting\n"
    end
  end

  def configure_mailers
    if exist?("app/mailers/application_mailer.rb")
      inject_into_class "app/mailers/application_mailer.rb", "ApplicationMailer", <<~RUBY.indent(2)
        # Links in emails point into the account they were sent from, including with deliver_later.
        def default_url_options
          super.merge(script_name: Current.account&.slug)
        end

      RUBY
    end
  end

  def configure_routes
    route "resources :accounts, only: :index" if authentication?
  end

  def add_migrations
    migration_template "db/migrate/create_accounts.rb", File.join(db_migrate_path, "create_accounts.rb")
    migration_template "db/migrate/create_memberships.rb", File.join(db_migrate_path, "create_memberships.rb") if authentication?
  end

  def create_test_files
    return unless exist?("test/test_helper.rb")

    template "test/fixtures/accounts.yml"
    template "test/fixtures/memberships.yml" if authentication?
    template "test/test_helpers/account_test_helper.rb"
    inject_into_file "test/test_helper.rb", "require_relative \"test_helpers/account_test_helper\"\n", after: "require \"rails/test_help\"\n"
  end

  private
    def authentication?
      exist?("app/controllers/concerns/authentication.rb") && exist?("app/models/user.rb")
    end

    def turbo?
      exist?("Gemfile") && File.read(File.join(destination_root, "Gemfile")).match?(/^\s*gem ["']turbo-rails["']/)
    end

    def migration_version
      "[#{ActiveRecord::Migration.current_version}]"
    end

    def exist?(path)
      File.exist?(File.join(destination_root, path))
    end
end
