# Tenanting

Multitenancy for Rails, generated into your app the same way `bin/rails generate authentication`
generates authentication.

```sh
bin/rails generate tenanting
```

Tenanting isn't a library you call at runtime. The generator writes a small amount of plain
Rails code into your app: `Current.account`, a model concern, a controller concern, a
middleware, and test helpers. You own that code, can read all of it in a few minutes, and can
change it when your app needs something different.

It's built for row-level multitenancy: every account-owned table has an `account_id` column,
and every query on those tables is scoped to the current account.

## Contents

- [Installation](#installation)
- [What gets generated](#what-gets-generated)
- [Scoping models](#scoping-models)
- [The current account](#the-current-account)
- [Controllers and URLs](#controllers-and-urls)
- [Background jobs, mailers, and broadcasts](#background-jobs-mailers-and-broadcasts)
- [Console, seeds, and data migrations](#console-seeds-and-data-migrations)
- [Testing](#testing)
- [Customizing](#customizing)
- [Security model](#security-model)
- [Migrating from ActsAsTenant](#migrating-from-actsastenant)
- [Development](#development)

## Installation

Tenanting requires Rails 8.0 or newer. The gem only contains the generator, so it only needs
to be in the development group:

```sh
bundle add tenanting --group development
```

If you want users who can belong to accounts, run the Rails authentication generator first.
Tenanting detects it and also adds memberships and an account picker.

```sh
bin/rails generate authentication   # optional
bin/rails generate tenanting
bin/rails db:migrate
```

Then scope your models to an account:

```ruby
class Project < ApplicationRecord
  scoped_to_account
end
```

## What gets generated

| File | What it does |
| --- | --- |
| `app/models/account.rb` | The tenant. `#slug` returns its URL prefix, `/123` |
| `app/models/current.rb` | Adds `attribute :account, :all_accounts` (created if it doesn't exist) |
| `app/models/concerns/account_scoping.rb` | `scoped_to_account`, included in `ApplicationRecord` |
| `app/controllers/concerns/tenanting.rb` | Sets `Current.account` for each request, included in `ApplicationController` |
| `config/initializers/tenanting.rb` | URL prefix middleware, plus the account for jobs, broadcasts, and the console |
| `db/migrate/*_create_accounts.rb` | The `accounts` table |
| `test/test_helpers/account_test_helper.rb` | `switch_to_account` for tests |
| `test/fixtures/accounts.yml` | Two accounts, `one` and `two` |

When the authentication generator has been run, you also get:

| File | What it does |
| --- | --- |
| `app/models/membership.rb` | Joins users to accounts. `User has_many :accounts, through: :memberships` |
| `app/controllers/accounts_controller.rb` | An account picker, at `/accounts` |
| `db/migrate/*_create_memberships.rb` | The `memberships` table, unique on user and account |
| `test/fixtures/memberships.yml` | Users `one` and `two` in accounts `one` and `two` |

The generator also includes `AccountScoping` in `ApplicationRecord`, adds `allow_accountless_access`
to the sessions and passwords controllers, and prefixes URLs in `ApplicationMailer` with the account.

## Scoping models

Call `scoped_to_account` in any model that belongs to an account. There are three ways to
connect a model to its account.

### Models with an `account_id` column

```sh
bin/rails generate model Project name:string account:references
```

```ruby
class Project < ApplicationRecord
  scoped_to_account

  has_many :tasks, dependent: :destroy

  validates :name, uniqueness: { scope: :account_id }
end
```

This adds `belongs_to :account` and a default scope on `Current.account`:

```ruby
Current.account = basecamp

Project.all               # SELECT * FROM projects WHERE account_id = 1
Project.find(other_id)    # Raises ActiveRecord::RecordNotFound for another account's project
Project.create!(name: "Launch").account  # => basecamp
```

### Models that belong to a scoped model: `through:`

Tables like `tasks` don't need their own `account_id` when their parent already has one. Scope
them through the parent's `belongs_to` association instead:

```ruby
class Task < ApplicationRecord
  belongs_to :project
  scoped_to_account through: :project
end

class Comment < ApplicationRecord
  belongs_to :task
  scoped_to_account through: :task
end
```

Queries filter on the parent's own scope, so chains of any depth work:

```sql
-- Task.all
SELECT * FROM tasks WHERE project_id IN (SELECT id FROM projects WHERE account_id = 1)

-- Comment.all
SELECT * FROM comments WHERE task_id IN (
  SELECT id FROM tasks WHERE project_id IN (SELECT id FROM projects WHERE account_id = 1))
```

Through models get `account` and `account_id` from their parent, and can't be created under,
or moved to, another account's parent. They can move to another parent in the same account.

An `account_id` column is still worth adding to large, frequently queried tables, because it
makes the scope a single indexed comparison instead of a subquery.

### Records that can exist outside of an account: `optional:`

```ruby
class Tag < ApplicationRecord
  scoped_to_account optional: true
end
```

The `account_id` column can be `NULL`, for records you create outside of any account, such as in
seeds or an admin area:

```ruby
AccountScoping.across_accounts { Tag.create!(name: "Urgent") }  # No account
```

Inside an account, records without an account are hidden, and new records always belong to the
current account. That keeps `Tag.delete_all` in one account from deleting records every account
shares. When an account should also see the shared records, ask for them explicitly:

```ruby
AccountScoping.across_accounts { Tag.where(account: [ Current.account, nil ]) }
```

`optional:` is for models with an `account_id` column. For a through model whose parent is
optional, make the `belongs_to` optional instead.

### Protections

The default scope uses `all_queries: true`, so it also applies to updating, deleting, and
reloading individual records, not just to reads. Scoped models also get three validations:

- **The account must be the current one.** Mass-assigning an `account_id`, like a scaffold's
  `params.expect(project: [ :name, :account_id ])`, can't create a record in another account.
  The same goes for a through model's parent, like a `project_id` from another account.
- **The account can't change** once a record is saved, including by moving a through model to a
  parent in another account.
- **`belongs_to` records must be in the same account.** `Task.create!(tag_id: params[:tag_id])`
  fails when the tag belongs to another account, whether it's assigned by ID or as a record.

Uniqueness validations are not scoped automatically. Add `scope: :account_id` where values only
need to be unique within an account.

## The current account

`Current.account` is an `ActiveSupport::CurrentAttributes` attribute, so it's isolated per
request, per job, and per thread, and reset automatically afterwards.

### Scoped models raise without an account

Querying a scoped model when `Current.account` isn't set raises
`AccountScoping::MissingAccountError`:

```ruby
Project.count
# => AccountScoping::MissingAccountError: Project is scoped to an account, but Current.account
#    isn't set. Use Current.set(account: account) { ... } or AccountScoping.across_accounts { ... }.
```

This is intentional. A job, rake task, or mailer that forgot to set an account fails loudly in
development instead of silently reading or writing every account's data in production. The same
applies to building records with `Project.new`, and to associations: `account.projects` raises
too, because the default scope still runs inside associations.

### Acting on behalf of an account

Set the account for a block. The previous value is restored afterwards:

```ruby
Current.set(account: account) do
  Project.create!(name: "Launch")
end
```

### Querying across accounts

When you mean to work with every account, say so:

```ruby
AccountScoping.across_accounts do
  Project.where(archived: true).delete_all
end
```

`across_accounts` only turns off account scoping. Unlike `unscoped`, other default scopes on the
model, such as a soft-delete scope, still apply. Both are easy to search for when reviewing code
that crosses accounts.

## Controllers and URLs

### Account URLs

Account URLs are prefixed with the account ID:

```
/123/projects/1
```

The `AccountSlug` middleware moves the `/123` prefix from `PATH_INFO` to `SCRIPT_NAME`, the same
way Rails handles an app mounted at a sub-path. This means:

- **Routes don't change.** No `scope ":account_id"` and no `:account_id` parameter to pass around.
- **URL helpers keep the prefix.** `project_path(@project)` returns `/123/projects/1`, and
  `redirect_to @project` stays inside the account.
- **Pages outside an account work unchanged**, like `/session/new` or `/accounts`.

To link into an account from outside it, pass its slug as the `script_name`:

```erb
<%= link_to account.name, root_url(script_name: account.slug) %>
```

To link out of an account, pass an empty `script_name`:

```ruby
redirect_to accounts_url(script_name: "")
```

### Requiring an account

`Tenanting` adds a `require_account` before action to `ApplicationController`. It reads the
account ID from the URL and sets `Current.account`. It works like the `Authentication` concern:

```ruby
class HomeController < ApplicationController
  allow_accountless_access only: :index
end
```

With authentication, the account is looked up through `Current.user.accounts`, so users can only
reach accounts they're members of. A URL for any other account returns 404 Not Found. A request
without an account prefix redirects to the account picker, which goes straight into the account
when the user only has one.

Without authentication, any account ID in the URL is accepted, and requests without one return
404. Add your own authorization in `find_account_by_slug`.

## Background jobs, mailers, and broadcasts

### Jobs

Every Active Job remembers the account it was enqueued in and runs in that account. This
includes mailers delivered with `deliver_later` and jobs that don't inherit from `ApplicationJob`:

```ruby
Current.set(account: account) do
  ExportJob.perform_later(project)  # Runs with Current.account = account
end
```

The account is serialized as a GlobalID in the job's `current_account` key. Arguments are
deserialized inside the account, so scoped records can be passed as arguments. A job enqueued
without an account raises `MissingAccountError` as soon as it queries a scoped model.

If the account is deleted before the job runs, the job raises `ActiveJob::DeserializationError`,
the same as when a record passed as an argument has been deleted. Unless it's handled, your queue
backend retries it and then marks it as failed. To drop these jobs instead, discard them in
`ApplicationJob`:

```ruby
class ApplicationJob < ActiveJob::Base
  discard_on ActiveJob::DeserializationError
end
```

### Mailers

`ApplicationMailer#default_url_options` adds the account prefix, so links in emails point into
the account the email was sent from. Set `config.action_mailer.default_url_options` with your
host as usual.

### Turbo Stream broadcasts

If your app uses `turbo-rails`, broadcasts render with the account prefix, so links in broadcast
partials point into the account. Broadcasts made with `broadcast_*_later` run as jobs, so they
pick up the account like any other job.

## Console, seeds, and data migrations

In the console, switch into an account before working with scoped models:

```ruby
>> switch_to_account 123
Switched to account 123 (Basecamp)
>> Project.count
=> 12
```

In seeds, data migrations, and rake tasks, wrap the work in `Current.set` or `across_accounts`:

```ruby
# db/seeds.rb
account = Account.create!(name: "Basecamp")

Current.set(account: account) do
  Project.create!(name: "Launch")
end
```

## Testing

Fixtures work as usual. Reference the account in each scoped fixture:

```yaml
# test/fixtures/projects.yml
one:
  name: Launch
  account: one
```

Fixture accessors like `projects(:one)` load records without the default scope, so they work
without an account. Call `switch_to_account` before running anything else that queries scoped
models:

```ruby
class ProjectTest < ActiveSupport::TestCase
  setup { switch_to_account accounts(:one) }

  test "names are unique within an account" do
    assert_not Project.new(name: projects(:one).name).valid?
  end
end
```

In integration tests, `switch_to_account` also prefixes generated URLs with the account, so each
request finds its account from the URL just like in production. It restores `Current.account`
after each request, because Rails resets `Current` around requests:

```ruby
class ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    switch_to_account accounts(:one)
  end

  test "create" do
    assert_difference -> { Project.count } do
      post projects_url, params: { project: { name: "Launch" } }  # POST /123/projects
    end
    assert_redirected_to project_url(Project.last)
  end

  test "another account's projects are not found" do
    get project_url(projects(:two))
    assert_response :not_found
  end
end
```

## Customizing

The generated code is yours to change. Some common changes:

### Subdomains or custom domains instead of a path prefix

Remove the `AccountSlug` middleware from `config/initializers/tenanting.rb`, add a column to
accounts, and look the account up from the request in the `Tenanting` concern:

```ruby
def find_account_by_slug
  Current.user&.accounts&.find_by(subdomain: request.subdomain)
end
```

Also change `Account#slug`, which is used as the URL prefix in mailers, broadcasts, and tests.
Instead, set the `host` in those places, or set `subdomain:` in your URL helpers.

### Public IDs instead of database IDs

`AccountSlug::PATTERN` matches a numeric first path segment. To keep database IDs out of URLs,
store a random public ID on each account, change the pattern to match it, look it up by that
column in `find_account_by_slug`, and return it from `Account#slug`.

Because any numeric first segment is treated as an account, avoid top-level routes whose path
starts with a number, or use a longer format (Fizzy pads IDs to at least 7 digits).

### Allowing unscoped queries

If you'd rather have queries run unscoped without an account, like ActsAsTenant's default,
replace the `raise` in `AccountScoping.scope_to_current_account` with `relation`. Consider
requiring the account in production anyway.

## Security model

Tenanting stops:

- Queries on scoped models from returning other accounts' records, including `update_all`,
  `delete_all`, and updates, deletes, and reloads of single records.
- Queries on scoped models from running when no account has been chosen.
- Records from being created in, or moved to, another account through mass assignment.
- `belongs_to` references to another account's records, by ID or by record.
- Users from reaching accounts they aren't members of (with authentication).
- Jobs from running in the wrong account, or in no account.

It does not cover:

- **Models without `scoped_to_account`.** Tables that aren't scoped, such as a join table that is
  only reached through a scoped model, rely on that model being scoped. Consider `through:`.
- **`unscoped`, raw SQL, and `across_accounts`.** These bypass scoping on purpose. Review them.
- **Polymorphic `belongs_to`.** These aren't checked by the same-account validation.
- **Cache keys.** Include the account in keys you build yourself, like
  `Rails.cache.fetch([ Current.account, "stats" ])`. Record-based cache keys are already unique.
- **Action Cable connections.** Identify the account in `ApplicationCable::Connection` yourself.
- **Active Storage.** Attachments are served by signed URLs, which aren't scoped to an account.

## Migrating from ActsAsTenant

| ActsAsTenant | Tenanting |
| --- | --- |
| `acts_as_tenant :account` | `scoped_to_account` |
| `acts_as_tenant :account, optional: true` | `scoped_to_account optional: true` |
| `acts_as_tenant :account, through: :account_users` | A `has_many :through`, like `User#accounts`. See below |
| `ActsAsTenant.current_tenant` | `Current.account` |
| `ActsAsTenant.current_tenant = account` | `Current.account = account` |
| `ActsAsTenant.with_tenant(account) { }` | `Current.set(account: account) { }` |
| `ActsAsTenant.without_tenant { }` | `AccountScoping.across_accounts { }` |
| `set_current_tenant_by_subdomain` | Path prefixes, or see [Subdomains](#subdomains-or-custom-domains-instead-of-a-path-prefix) |
| `set_current_tenant_through_filter` | Edit `find_account_by_slug` |
| `config.require_tenant = true` | Always on |
| `validates_uniqueness_to_tenant :name` | `validates :name, uniqueness: { scope: :account_id }` |
| `ActsAsTenant::ActiveJobExtensions` | Built in, for every Active Job |
| `ActsAsTenant::TestTenantMiddleware` | `switch_to_account` |

To migrate:

1. Run `bin/rails generate tenanting`. If your tenant model already exists, delete the generated
   `Account` model and migration and keep yours. Add `#slug` to it.
2. Replace `acts_as_tenant :account` with `scoped_to_account` in each model. Models that only
   reach their account through a parent can use `scoped_to_account through: :parent`.

   ActsAsTenant's `through:` is different: it scopes a model like `User` to accounts through a
   many-to-many join table. Records like that belong to several accounts, so they aren't scoped.
   Reach them through an association instead, like `Current.account.users`.
3. Replace `ActsAsTenant` calls using the table above.
4. Remove your `set_current_tenant_*` calls. `Tenanting` sets `Current.account` from the URL, or
   from wherever you change `find_account_by_slug` to look.
5. Wrap code that ran without a tenant in `Current.set` or `across_accounts`. Your test suite will
   point these out by raising `AccountScoping::MissingAccountError`.
6. Remove the `acts_as_tenant` gem.

## Development

```sh
bundle install
bundle exec rake test              # Generator tests
bundle exec rake test:integration  # Generates a Rails app and runs its tests
```

The integration task creates a new Rails app, runs the authentication and tenanting generators,
adds the models and tests in `test/integration/app`, and runs the app's test suite.

## License

Tenanting is released under the [MIT License](MIT-LICENSE).
