require "test_helper"

class AccountTest < ActiveSupport::TestCase
  test "finds accounts by subdomain" do
    assert_equal accounts(:one), Account.find_by_host("one.example.com")
    assert_nil Account.find_by_host("deep.one.example.com")
    assert_nil Account.find_by_host("example.com")
  end

  test "finds accounts by custom domain" do
    accounts(:one).update!(domain: "Projects.One.test.")

    assert_equal "projects.one.test", accounts(:one).domain
    assert_equal accounts(:one), Account.find_by_host("projects.one.test")
  end

  test "host is the custom domain, or the subdomain of the app's domain" do
    assert_equal "one.example.com", accounts(:one).host

    accounts(:one).update!(domain: "projects.one.test")
    assert_equal "projects.one.test", accounts(:one).host
  end

  test "blank custom domains are removed" do
    accounts(:one).update!(domain: " ")
    assert_nil accounts(:one).domain
  end

  test "subdomains default to the name" do
    assert_equal "acme-corp", Account.create!(name: "Acme Corp").subdomain
    assert_equal "acme", Account.create!(name: "Acme Corp", subdomain: "acme").subdomain
  end

  test "subdomains must be valid, unique, and not reserved" do
    assert_not Account.new(name: "Bad", subdomain: "no_underscores").valid?
    assert_not Account.new(name: "Taken", subdomain: "ONE").valid?
    assert_not Account.new(name: "Reserved", subdomain: "www").valid?
    assert Account.new(name: "Good", subdomain: "good-one").valid?
  end

  test "custom domains can't be on the app's domain" do
    account = Account.new(name: "Sneaky", subdomain: "sneaky", domain: "two.example.com")

    assert_not account.valid?
    assert_match "must be your own domain", account.errors[:domain].first
  end
end
