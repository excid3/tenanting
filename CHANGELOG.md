# Changelog

## Unreleased

- `--account-from=cookie` keeps the current account in a signed cookie instead of the URL.
  Controllers choose the account with `switch_to_account`
- Jobs whose account was deleted after they were enqueued raise
  `ActiveJob::DeserializationError`, so `discard_on` and `retry_on` can handle them

## 0.1.0 (2026-09-21)

- Initial release: `bin/rails generate tenanting`
- `scoped_to_account` in models, with `through:` for models scoped by a parent and `optional:`
  for records that can exist outside of an account
