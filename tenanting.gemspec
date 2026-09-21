# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "tenanting"
  spec.version = "0.1.0"
  spec.authors = [ "Chris Oliver" ]
  spec.email = [ "excid3@gmail.com" ]

  spec.summary = "A multitenancy generator for Rails, in the style of the authentication generator"
  spec.description = "Generates account-based multitenancy into your Rails app: Current.account, " \
    "scoped models that fail closed, account URL prefixes, and account-aware jobs, mailers, and tests."
  spec.homepage = "https://github.com/excid3/tenanting"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*", "MIT-LICENSE", "README.md", "CHANGELOG.md"]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "railties", ">= 8.0"
  spec.add_dependency "activerecord", ">= 8.0"
end
